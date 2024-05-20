#[allow(implicit_const_copy)]
/// Implementation a cross-chain messaging system for Axelar.
///
/// This code is based on the following:
///
/// - When call approvals is sent to Sui, it targets an object and not a module;
/// - To support cross-chain messaging, a Channel object has to be created;
/// - Channel can be either owned or shared but not frozen;
/// - Module developer on the Sui side will have to implement a system to support messaging;
/// - Checks for uniqueness of approvals should be done through `Channel`s to avoid big data storage;
///
/// I. Sending call approvals
///
/// A approval is sent through the `send` function, a Channel is supplied to determine the source -> ID.
/// Event is then emitted and Axelar network can operate
///
/// II. Receiving call approvals
///
/// Approval bytes and signatures are passed into `create` function to generate a CallApproval object.
///  - Signatures are checked against the known set of validators.
///  - CallApproval bytes are parsed to determine: source, destination_chain, payload and destination_id
///  - `destination_id` points to a `Channel` object
///
/// Once created, `CallApproval` needs to be consumed. And the only way to do it is by calling
/// `consume_call_approval` function and pass a correct `Channel` instance alongside the `CallApproval`.
///  - CallApproval is checked for uniqueness (for this channel)
///  - CallApproval is checked to match the `Channel`.id
///
module axelar_gateway::gateway {
    use std::ascii::{Self, String};

    use sui::bcs;
    use sui::hash;
    use sui::table::{Self, Table};
    use sui::address;

    use axelar_gateway::message::{Self};
    use axelar_gateway::bytes32::{Self, Bytes32};
    use axelar_gateway::utils::{to_sui_signed};
    use axelar_gateway::channel::{Self, Channel, ApprovedCall};
    use axelar_gateway::auth::{Self, AxelarValidators, validate_proof};
    use axelar_gateway::weighted_signers::{Self};

    /// ------
    /// Errors
    /// ------
    /// For when number of commands does not match number of command ids.
    const EInvalidCommands: u64 = 0;
    /// For when approval chainId is not SUI.
    const EInvalidChain: u64 = 1;
    /// Trying to `take_approved_call` with a wrong payload.
    const EPayloadHashMismatch: u64 = 2;
    /// Invalid length of vector
    const EInvalidLength: u64 = 3;
    /// Remaining data after BCS decoding
    const ERemainingData: u64 = 4;

    /// -----
    /// Types
    /// -----
    const COMMAND_TYPE_APPROVE_MESSAGES: u8 = 0;
    const COMMAND_TYPE_ROTATE_SIGNERS: u8 = 1;

    // These are currently supported
    const SELECTOR_APPROVE_CONTRACT_CALL: vector<u8> = b"approveContractCall";
    const SELECTOR_TRANSFER_OPERATORSHIP: vector<u8> = b"transferOperatorship";

    /// An object holding the state of the Axelar bridge.
    /// The central piece in managing call approval creation and signature verification.
    public struct Gateway has key {
        id: UID,
        approvals: Table<address, Approval>,  // TODO: remove
        messages: Table<vector<u8>, MessageStatus>,
        validators: AxelarValidators,
    }

    /// The State of the message.
    /// Can be either one of three states:
    /// - Non-existent: Set to bytes32(0)
    /// - Approved: Set to the hash of the message
    /// - Executed: Set to bytes32(1)
    public struct MessageStatus has store {
        state: vector<u8>,
    }

    /// CallApproval struct which can consumed only by a `Channel` object.
    /// Does not require additional generic field to operate as linking
    /// by `id_bytes` is more than enough.
    public struct Approval has store {
        /// Hash of the cmd_id, destination_id, source_chain, source_address, payload_hash
        approval_hash: vector<u8>,
    }

    /// ------
    /// Events
    /// ------

    /// Emitted when a new message is sent from the SUI network.
    public struct ContractCall has copy, drop {
        source_id: address,
        destination_chain: String,
        destination_address: String,
        payload: vector<u8>,
        payload_hash: address,
    }

    /// Emitted when a new message is approved by the SUI network.
    public struct ContractCallApproved has copy, drop {
        cmd_id: address,
        source_chain: String,
        source_address: String,
        destination_id: address,
        payload_hash: address,
    }

    /// Emitted when a new message is approved by the gateway.
    public struct MessageApproved has copy, drop {
        message: message::Message,
    }

    fun init(ctx: &mut TxContext) {
        let gateway = Gateway {
            id: object::new(ctx),
            approvals: table::new(ctx),
            messages: table::new(ctx),
            validators: auth::new(),
        };

        transfer::share_object(gateway);
    }

    /// ----------------
    /// Public Functions
    /// ----------------

    /// Call a contract on the destination chain by sending an event from an
    /// authorized Channel. Currently we require Channel to be mutable to prevent
    /// frozen object scenario or when someone exposes the Channel to the outer
    /// world. However, this restriction may be lifted in the future, and having
    /// an immutable reference should be enough.
    public fun call_contract(
        channel: &Channel,
        destination_chain: String,
        destination_address: String,
        payload: vector<u8>
    ) {
        sui::event::emit(ContractCall {
            source_id: object::id_address(channel),
            destination_chain,
            destination_address,
            payload,
            payload_hash: address::from_bytes(hash::keccak256(&payload)),
        })
    }

    /// -----------
    /// Entrypoints
    /// -----------

    /// The main entrypoint for approving Axelar signed messages.
    /// If proof is valid, message approvals are stored in the Gateway object, if not already approved before.
    /// This method is only intended to be called via a Transaction Block, keeping more flexibility for upgrades.
    entry fun approve_messages(
        self: &mut Gateway,
        message_data: vector<u8>,
        proof: vector<u8>,
    ) {
        let messages = peel_messages(*&message_data);

        let _ = self.validators.validate_proof(data_hash(COMMAND_TYPE_APPROVE_MESSAGES, message_data).to_bytes(), proof);

        let mut i = 0;

        while (i < messages.length()) {
            self.approve_message(&messages[i]);

            i = i + 1;
        };
    }

    /// The main entrypoint for rotating Axelar signers.
    /// If proof is valid, signers stored on the Gateway object are rotated.
    /// This method is only intended to be called via a Transaction Block, keeping more flexibility for upgrades.
    entry fun rotate_signers(
        self: &mut Gateway,
        new_signers_data: vector<u8>,
        proof: vector<u8>,
    ) {
        let weighted_signers = peel_weighted_signers(new_signers_data);

        let _ = self.validators.validate_proof(data_hash(COMMAND_TYPE_ROTATE_SIGNERS, new_signers_data).to_bytes(), proof);

        // This will fail if signers are duplicated
        self.validators.rotate_signers(weighted_signers);
    }

    /// -----------------
    /// Private Functions
    /// -----------------

    fun peel_messages(message_data: vector<u8>): vector<message::Message> {
        let mut bcs = bcs::new(message_data);

        let mut messages = vector::empty<message::Message>();
        let mut len = bcs.peel_vec_length();

        while (len > 0) {
            messages.push_back(message::peel(&mut bcs));

            len = len - 1;
        };

        assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);
        assert!(messages.length() > 0, EInvalidLength);

        messages
    }

    fun peel_weighted_signers(weighted_signers_data: vector<u8>): weighted_signers::WeightedSigners {
        let mut bcs = bcs::new(weighted_signers_data);

        let weighted_signers = weighted_signers::from_bcs(&mut bcs);

        assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);

        weighted_signers
    }

    fun data_hash(command_type: u8, data: vector<u8>): Bytes32 {
        let mut typed_data = vector::singleton(command_type);
        typed_data.append(data);

        bytes32::new(hash::keccak256(&typed_data))
    }

    fun approve_message(
        self: &mut Gateway,
        message: &message::Message,
    ) {
        let command_id = hash::keccak256(&message.id());

        // If the message was already approved, ignore it.
        if (self.messages.contains(command_id)) {
            return
        };

        self.messages.add(
            command_id,
            MessageStatus { state: bcs::to_bytes(message) }
        );

        sui::event::emit(MessageApproved {
            message: *message,
        });
    }

    // TODO: remove legacy methods
    #[allow(implicit_const_copy)]
    /// The main entrypoint for the external approval processing.
    /// Parses data and attaches call approvals to the Axelar object to be
    /// later picked up and consumed by their corresponding Channel.
    ///
    /// Aborts with multiple error codes, ignores call approval which are not
    /// supported by the current implementation of the protocol.
    ///
    /// Input data must be serialized with BCS (see specification here: https://github.com/diem/bcs).
    public entry fun process_commands(
        self: &mut Gateway,
        input: vector<u8>
    ) {
        let mut bytes = bcs::new(input);
        // Split input into:
        // data: vector<u8> (BCS bytes)
        // proof: vector<u8> (BCS bytes)
        let (data, proof) = (
            bytes.peel_vec_u8(),
            bytes.peel_vec_u8()
        );
        let mut allow_operatorship_transfer = validate_proof(borrow_validators(self), to_sui_signed(*&data), proof);

        // Treat `data` as BCS bytes.
        let mut data_bcs = bcs::new(data);

        // Split data into:
        // chain_id: u64,
        // command_ids: vector<vector<u8>> (vector<string>)
        // commands: vector<vector<u8>> (vector<string>)
        // params: vector<vector<u8>> (vector<byteArray>)
        let chain_id = data_bcs.peel_u64();
        let command_ids = data_bcs.peel_vec_address();
        let commands = data_bcs.peel_vec_vec_u8();
        let params = data_bcs.peel_vec_vec_u8();
        assert!(chain_id == 1, EInvalidChain);

        let (mut i, commands_len) = (0, vector::length(&commands));

        // make sure number of commands passed matches command IDs
        assert!(vector::length(&command_ids) == commands_len, EInvalidCommands);
        // make sure number of commands passed matches params
        assert!(vector::length(&params) == commands_len, EInvalidCommands);

        while (i < commands_len) {
            // TODO: this does not store executed cmd_ids in the gateway, which make too many assumptions for the axelar network that it shouldn't.
            let cmd_id = *vector::borrow(&command_ids, i);
            let cmd_selector = vector::borrow(&commands, i);
            let payload = *vector::borrow(&params, i);
            i = i + 1;

            // Build a `CallApproval` object from the `params[i]`. BCS serializes data
            // in order, so field reads have to be done carefully and in order!
            if (cmd_selector == &SELECTOR_APPROVE_CONTRACT_CALL) {
                let mut payload = bcs::new(payload);
                let (source_chain, source_address, destination_id, payload_hash) = (
                    ascii::string(payload.peel_vec_u8()),
                    ascii::string(payload.peel_vec_u8()),
                    payload.peel_address(),
                    payload.peel_address()
                );
                add_approval(self,
                    cmd_id, source_chain, source_address, destination_id, payload_hash
                );

                sui::event::emit(ContractCallApproved {
                    cmd_id, source_chain, source_address, destination_id, payload_hash
                });
                continue
            } else if (cmd_selector == &SELECTOR_TRANSFER_OPERATORSHIP) {
                if (!allow_operatorship_transfer) {
                    continue
                };
                allow_operatorship_transfer = false;
                borrow_mut_validators(self).transfer_operatorship(payload);
            } else {
                continue
            };
        };
    }

    /// Most common scenario would be to target a shared object, however this
    /// messaging system allows sending private messages which can be consumed
    /// by single-owner targets.
    ///
    /// The hot potato approvel call object is returned.
    public fun take_approved_call(
        self: &mut Gateway,
        cmd_id: address,
        source_chain: String,
        source_address: String,
        destination_id: address,
        payload: vector<u8>
    ): ApprovedCall {
        let Approval {
            approval_hash,
        } = table::remove(&mut self.approvals, cmd_id);

        let computed_approval_hash = get_approval_hash(
            &cmd_id,
            &source_chain,
            &source_address,
            &destination_id,
            &address::from_bytes(hash::keccak256(&payload)),
        );
        assert!(computed_approval_hash == approval_hash, EPayloadHashMismatch);

        // Friend only.
        channel::create_approved_call(
            cmd_id,
            source_chain,
            source_address,
            destination_id,
            payload,
        )
    }

    fun get_approval_hash(
        cmd_id: &address,
        source_chain: &String,
        source_address: &String,
        destination_id: &address,
        payload_hash: &address
    ): vector<u8> {
        let mut data = vector[];
        vector::append(&mut data, bcs::to_bytes(cmd_id));
        vector::append(&mut data, bcs::to_bytes(destination_id));
        vector::append(&mut data, bcs::to_bytes(source_chain));
        vector::append(&mut data, bcs::to_bytes(source_address));
        vector::append(&mut data, bcs::to_bytes(payload_hash));

        hash::keccak256(&data)
    }


    fun add_approval(
        self: &mut Gateway,
        cmd_id: address,
        source_chain: String,
        source_address: String,
        destination_id: address,
        payload_hash: address
    ) {
        table::add(&mut self.approvals, cmd_id, Approval {
            approval_hash: get_approval_hash(
                &cmd_id,
                &source_chain,
                &source_address,
                &destination_id,
                &payload_hash,
            ),
        });
    }

    fun borrow_validators(self: &Gateway): &AxelarValidators {
        &self.validators
    }

    fun borrow_mut_validators(self: &mut Gateway): &mut AxelarValidators {
        &mut self.validators
    }

    #[test_only]
    public fun new(ctx: &mut TxContext): Gateway {
        Gateway {
            id: object::new(ctx),
            approvals: table::new(ctx),
            messages: table::new(ctx),
            validators: auth::new(),
        }
    }

    #[test_only]
    public fun get_approval_params(source_chain: &ascii::String, source_address: &ascii::String, destination_id: &address, payload_hash: &address): vector<u8> {
        let mut bcs = vector::empty<u8>();
        vector::append(&mut bcs, bcs::to_bytes(source_chain));
        vector::append(&mut bcs, bcs::to_bytes(source_address));
        vector::append(&mut bcs, bcs::to_bytes(destination_id));
        vector::append(&mut bcs, bcs::to_bytes(payload_hash));
        bcs
    }

    #[test_only]
    public fun get_data(chain_id: &u64, command_ids: &vector<address>, commands: &vector<vector<u8>>, params: &vector<vector<u8>>): vector<u8> {
        let mut bcs = vector::empty<u8>();
        vector::append(&mut bcs, bcs::to_bytes(chain_id));
        vector::append(&mut bcs, bcs::to_bytes(command_ids));
        vector::append(&mut bcs, bcs::to_bytes(commands));
        vector::append(&mut bcs, bcs::to_bytes(params));
        bcs
    }

    #[test]
    fun test_process_commands() {
        let ctx = &mut sui::tx_context::dummy();
        let mut gateway = new(ctx);

        let source_chain = ascii::string(b"Source Chain");
        let source_address = ascii::string(b"Source Address");
        let destination_id = @0x3;
        let payload_hash = @0x4;
        let approval_params = get_approval_params(&source_chain, &source_address, &destination_id, &payload_hash);

        let new_operators_1 = vector[x"1234", x"5678"];
        let new_weights_1 = vector[1u128, 2u128];
        let new_threshold_1 = 2u128;
        let transfer_params_1 = auth::get_transfer_params(&new_operators_1, &new_weights_1, &new_threshold_1);

        let new_operators_2 = vector[x"90ab", x"cdef"];
        let new_weights_2 = vector[3u128, 4u128];
        let new_threshold_2 = 5u128;
        let transfer_params_2 = auth::get_transfer_params(&new_operators_2, &new_weights_2, &new_threshold_2);

        let chain_id = 1u64;
        let command_ids = vector[@0x1, @0x2, @0x3];
        let commands = vector[SELECTOR_APPROVE_CONTRACT_CALL, SELECTOR_TRANSFER_OPERATORSHIP, SELECTOR_TRANSFER_OPERATORSHIP];
        let params = vector[
            approval_params,
            transfer_params_1,
            transfer_params_2,
        ];

        let data = get_data(&chain_id, &command_ids, &commands, &params);
        let proof = x"";
        let mut input = vector[];

        vector::append(&mut input, bcs::to_bytes(&data));
        vector::append(&mut input, bcs::to_bytes(&proof));

        assert!(gateway.approvals.contains(@0x1) == false, 0);
        assert!(gateway.validators.epoch() == 0, 3);

        process_commands(&mut gateway, input);

        assert!(gateway.approvals.contains(@0x1) == true, 2);
        let approval_hash = get_approval_hash(
            &@0x1,
            &source_chain,
            &source_address,
            &destination_id,
            &payload_hash,
        );

        assert!(approval_hash == gateway.approvals.borrow(@0x1).approval_hash, 3);
        assert!(gateway.validators.epoch() == 1, 4);

        assert!(gateway.validators.test_contains_operators(
            &new_operators_1,
            &new_weights_1,
            new_threshold_1,
        ) == true, 5);
        assert!(gateway.validators.test_contains_operators(
            &new_operators_2,
            &new_weights_2,
            new_threshold_2,
        ) == false, 6);
        assert!(gateway.validators.test_epoch_for_operators(
            &new_operators_1,
            &new_weights_1,
            new_threshold_1,
        ) == 1, 7);


        sui::test_utils::destroy(gateway);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidChain)]
    fun test_process_commands_invalid_chain() {
        let ctx = &mut sui::tx_context::dummy();
        let mut gateway = new(ctx);

        let chain_id = 2u64;
        let command_ids = vector[];
        let commands = vector[];
        let params = vector[];

        let data = get_data(&chain_id, &command_ids, &commands, &params);
        let proof = x"";
        let mut input = vector[];

        vector::append(&mut input, bcs::to_bytes(&data));
        vector::append(&mut input, bcs::to_bytes(&proof));

        process_commands(&mut gateway, input);

        sui::test_utils::destroy(gateway);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidCommands)]
    fun test_process_commands_invalid_commands_commands() {
        let ctx = &mut sui::tx_context::dummy();
        let mut gateway = new(ctx);

        let chain_id = 1u64;
        let command_ids = vector[];
        let commands = vector[SELECTOR_APPROVE_CONTRACT_CALL];
        let params = vector[];

        let data = get_data(&chain_id, &command_ids, &commands, &params);
        let proof = x"";
        let mut input = vector[];

        vector::append(&mut input, bcs::to_bytes(&data));
        vector::append(&mut input, bcs::to_bytes(&proof));

        process_commands(&mut gateway, input);

        sui::test_utils::destroy(gateway);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidCommands)]
    fun test_process_commands_invalid_commands_params() {
        let ctx = &mut sui::tx_context::dummy();
        let mut gateway = new(ctx);

        let chain_id = 1u64;
        let command_ids = vector[];
        let commands = vector[];
        let params = vector[x""];

        let data = get_data(&chain_id, &command_ids, &commands, &params);
        let proof = x"";
        let mut input = vector[];

        vector::append(&mut input, bcs::to_bytes(&data));
        vector::append(&mut input, bcs::to_bytes(&proof));

        process_commands(&mut gateway, input);

        sui::test_utils::destroy(gateway);
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldAlreadyExists)]
    fun test_process_same_approval_twice() {
        let ctx = &mut sui::tx_context::dummy();
        let mut gateway = new(ctx);

        let source_chain_1 = ascii::string(b"Source Chain 1");
        let source_address_1 = ascii::string(b"Source Address 1");
        let destination_id_1 = @0x3;
        let payload_hash_1 = @0x4;
        let approval_params_1 = get_approval_params(&source_chain_1, &source_address_1, &destination_id_1, &payload_hash_1);

        let source_chain_2 = ascii::string(b"Source Chain 2");
        let source_address_2 = ascii::string(b"Source Address 2");
        let destination_id_2 = @0x5;
        let payload_hash_2 = @0x6;
        let approval_params_2 = get_approval_params(&source_chain_2, &source_address_2, &destination_id_2, &payload_hash_2);

        let chain_id = 1u64;
        let command_ids = vector[@0x1, @0x1];
        let commands = vector[SELECTOR_APPROVE_CONTRACT_CALL, SELECTOR_APPROVE_CONTRACT_CALL];
        let params = vector[
            approval_params_1,
            approval_params_2,
        ];

        let data = get_data(&chain_id, &command_ids, &commands, &params);
        let proof = x"";
        let mut input = vector[];

        vector::append(&mut input, bcs::to_bytes(&data));
        vector::append(&mut input, bcs::to_bytes(&proof));

        assert!(gateway.approvals.contains(@0x1) == false, 0);

        process_commands(&mut gateway, input);

        sui::test_utils::destroy(gateway);
    }
}
