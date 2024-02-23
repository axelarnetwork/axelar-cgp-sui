// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

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
///  - CallApproval bytes are parsed to determine: source, destination_chain, payload and target_id
///  - `target_id` points to a `Channel` object
///
/// Once created, `CallApproval` needs to be consumed. And the only way to do it is by calling
/// `consume_call_approval` function and pass a correct `Channel` instance alongside the `CallApproval`.
///  - CallApproval is checked for uniqueness (for this channel)
///  - CallApproval is checked to match the `Channel`.id
///
module axelar::gateway {
    use std::ascii::{Self, String};
    use std::vector;
    use std::type_name;

    use sui::bcs;
    use sui::hash;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::table::{Self, Table};
    use sui::address;
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::hex;

    use axelar::utils::{to_sui_signed, abi_decode_fixed, abi_decode_variable};
    use axelar::channel::{Self, Channel, ApprovedCall};
    use axelar::validators::{Self, AxelarValidators, validate_proof};

    /// For when approval signatures failed verification.
    // const ESignatureInvalid: u64 = 1;

    /// For when number of commands does not match number of command ids.
    const EInvalidCommands: u64 = 4;

    /// For when approval chainId is not SUI.
    const EInvalidChain: u64 = 3;

    /// Trying to `take_approved_call` with a wrong payload.
    const EPayloadHashMismatch: u64 = 5;

    const EInvalidUpgradeCap: u64 = 6;

    const EUntrustedAddress: u64 = 7;
    const EInvalidMessageType: u64 = 8;

    // These are currently supported
    const SELECTOR_APPROVE_CONTRACT_CALL: vector<u8> = b"approveContractCall";
    const SELECTOR_TRANSFER_OPERATORSHIP: vector<u8> = b"transferOperatorship";

    // address::to_u256(address::from_bytes(keccak256(b"sui-authorize-upgrade")));
    const MESSAGE_TYPE_AUTHORIZE_UPGRADE: u256 = 0x6650591a2a5ddb76c14dc3391ca387db8ca4fe939511ec09c8f71edeadbc8efb;

    /// An object holding the state of the Axelar bridge.
    /// The central piece in managing call approval creation and signature verification.
    public struct Gateway has key {
        id: UID,
        approvals: Table<address, Approval>,
        validators: AxelarValidators,
    }

    /// CallApproval struct which can consumed only by a `Channel` object.
    /// Does not require additional generic field to operate as linking
    /// by `id_bytes` is more than enough.
    public struct Approval has store {
        /// Hash of the cmd_id, target_id, source_chain, source_address, payload_hash
        approval_hash: vector<u8>,
    }

    /// Emitted when a new message is sent from the SUI network.
    public struct ContractCall has copy, drop {
        source_id: address,
        destination_chain: String,
        destination_address: String,
        payload: vector<u8>,
        payload_hash: address,
    }

    /// Event: emitted when a new message is approved by the SUI network.
    public struct ContractCallApproved has copy, drop {
        cmd_id: address,
        source_chain: String,
        source_address: String,
        target_id: address,
        payload_hash: address,
    }


    fun init(ctx: &mut TxContext) {
        let gateway = Gateway {
            id: object::new(ctx),
            approvals: table::new(ctx),
            validators: validators::new(),
        };

        transfer::share_object(gateway);
    }

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
            let cmd_id = *vector::borrow(&command_ids, i);
            let cmd_selector = vector::borrow(&commands, i);
            let payload = *vector::borrow(&params, i);
            i = i + 1;

            // Build a `CallApproval` object from the `params[i]`. BCS serializes data
            // in order, so field reads have to be done carefully and in order!
            if (cmd_selector == &SELECTOR_APPROVE_CONTRACT_CALL) {
                let mut payload = bcs::new(payload);
                let (source_chain, source_address, target_id, payload_hash) = (
                    ascii::string(payload.peel_vec_u8()),
                    ascii::string(payload.peel_vec_u8()),
                    payload.peel_address(),
                    payload.peel_address()
                );
                add_approval(self,
                    cmd_id, source_chain, source_address, target_id, payload_hash
                );

                sui::event::emit(ContractCallApproved {
                    cmd_id, source_chain, source_address, target_id, payload_hash
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
        target_id: address,
        payload: vector<u8>
    ): ApprovedCall {
        let Approval {
            approval_hash,
        } = table::remove(&mut self.approvals, cmd_id);

        let mut data = vector[];
        vector::append(&mut data, address::to_bytes(cmd_id));
        vector::append(&mut data, address::to_bytes(target_id));
        vector::append(&mut data, *ascii::as_bytes(&source_chain));
        vector::append(&mut data, *ascii::as_bytes(&source_address));
        vector::append(&mut data, hash::keccak256(&payload));

        assert!(hash::keccak256(&data) == approval_hash, EPayloadHashMismatch);

        // Friend only.
        channel::create_approved_call(
            cmd_id,
            source_chain,
            source_address,
            target_id,
            payload,
        )
    }

    /// Call a contract on the destination chain by sending an event from an
    /// authorized Channel. Currently we require Channel to be mutable to prevent
    /// frozen object scenario or when someone exposes the Channel to the outer
    /// world. However, this restriction may be lifted in the future, and having
    /// an immutable reference should be enough.
    public fun call_contract(
        channel: &mut Channel,
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


    fun add_approval(
        self: &mut Gateway,
        cmd_id: address,
        source_chain: String,
        source_address: String,
        target_id: address,
        payload_hash: address
    ) {
        let mut data = vector[];
        vector::append(&mut data, address::to_bytes(cmd_id));
        vector::append(&mut data, address::to_bytes(target_id));
        vector::append(&mut data, *ascii::as_bytes(&source_chain));
        vector::append(&mut data, *ascii::as_bytes(&source_address));
        vector::append(&mut data, address::to_bytes(payload_hash));

        table::add(&mut self.approvals, cmd_id, Approval {
            approval_hash: hash::keccak256(&data),
        });
    }

    fun borrow_validators(self: &Gateway): &AxelarValidators {
        &self.validators
    }

    fun borrow_mut_validators(self: &mut Gateway): &mut AxelarValidators {
        &mut self.validators
    }
    

    #[test_only]
    use axelar::utils::operators_hash;
    #[test_only]
    use sui::vec_map;

    #[test_only]
    /// Test call approval for the `test_execute` test.
    /// Generated via the `presets` script.
    const CALL_APPROVAL: vector<u8> = x"ce01010000000000000002000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020213617070726f7665436f6e747261637443616c6c13617070726f7665436f6e747261637443616c6c022b034554480330783000000000000000000000000000000000000000000000000000000000000004000000002e064158454c415203307831000000000000000000000000000000000000000000000000000000000000040000000087010121037286a4f1177bea06c8e15cf6ec3df0b7747a01ac2329ca2999dfd74eff59902801640000000000000000000000000000000a00000000000000000000000000000001410359561d86366875003ace8879abf953972034221461896d5098873ebe0b30ed6ef06560cc0adccedc8dd09d2a2bca7bfd22ca09d53c034a1aacfffefad0a6000000";

    #[test_only]
    const TRANSFER_OPERATORSHIP_APPROVAL: vector<u8> = x"8501010000000000000001000000000000000000000000000000000000000000000000000000000000000101147472616e736665724f70657261746f727368697001440121037286a4f1177bea06c8e15cf6ec3df0b7747a01ac2329ca2999dfd74eff59902801c80000000000000000000000000000001400000000000000000000000000000087010121037286a4f1177bea06c8e15cf6ec3df0b7747a01ac2329ca2999dfd74eff59902801640000000000000000000000000000000a000000000000000000000000000000014198b04944e2009969c93226ec6c97a7b9cc655b4ac52f7eeefd6cf107981c063a56a419cb149ea8a9cd49e8c745c655c5ccc242d35a9bebe7cebf6751121092a30100";

    #[test]
    /// Tests execution with a set of validators.
    /// Samples for this test are generated with the `presets/` application.
    fun test_execute() {
        let ctx = &mut sui::tx_context::dummy();

        // public keys of `operators`
        let epoch = 1;
        let operators = vector[
            x"037286a4f1177bea06c8e15cf6ec3df0b7747a01ac2329ca2999dfd74eff599028"
        ];

        let mut epoch_for_hash = vec_map::empty();
        epoch_for_hash.insert(
            operators_hash(&operators, &vector[100u128], 10u128),
            epoch
        );

        // create validators for testing
        let mut validators = validators::new(
            epoch,
            epoch_for_hash,
            ctx
        );

        process_commands(&mut validators, CALL_APPROVAL);

        validators.remove_approval_for_test(@0x1);
        validators.remove_approval_for_test(@0x2);
        sui::test_utils::destroy(validators);
    }

    #[test]
    fun test_transfer_operatorship() {
        let ctx = &mut sui::tx_context::dummy();
        // public keys of `operators`
        let epoch = 1;
        let operators = vector[
            x"037286a4f1177bea06c8e15cf6ec3df0b7747a01ac2329ca2999dfd74eff599028"
        ];

        let mut epoch_for_hash = vec_map::empty();
        let operators_hash = operators_hash(&operators, &vector[100u128], 10u128);
        epoch_for_hash.insert(operators_hash, epoch);

        // create validators for testing
        let mut validators = validators::new(
            epoch,
            epoch_for_hash,
            ctx
        );
        process_commands(&mut validators, TRANSFER_OPERATORSHIP_APPROVAL);
        assert!(validators.epoch() == 2, 0);

        sui::test_utils::destroy(validators);
    }
}
