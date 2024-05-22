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
///  - Signatures are checked against the known set of signers.
///  - CallApproval bytes are parsed to determine: source, destination_chain, payload and destination_id
///  - `destination_id` points to a `Channel` object
///
/// Once created, `CallApproval` needs to be consumed. And the only way to do it is by calling
/// `consume_call_approval` function and pass a correct `Channel` instance alongside the `CallApproval`.
///  - CallApproval is checked for uniqueness (for this channel)
///  - CallApproval is checked to match the `Channel`.id
///
module axelar_gateway::gateway {
    use std::ascii::{String};

    use sui::bcs;
    use sui::hash;
    use sui::table::{Self, Table};
    use sui::address;

    use axelar_gateway::message::{Self, Message};
    use axelar_gateway::bytes32::{Self, Bytes32};
    use axelar_gateway::channel::{Self, Channel, ApprovedCall};
    use axelar_gateway::auth::{Self, AxelarSigners, validate_proof};
    use axelar_gateway::weighted_signers::{Self, WeightedSigners};
    use axelar_gateway::proof::{Self, Proof};

    /// ------
    /// Errors
    /// ------
    /// Trying to `take_approved_call` with a wrong payload.
    const EPayloadHashMismatch: u64 = 2;
    /// Invalid length of vector
    const EInvalidLength: u64 = 3;
    /// Remaining data after BCS decoding
    const ERemainingData: u64 = 4;
    /// Not latest signers
    const ENotLatestSigners: u64 = 5;

    // -----
    // Types
    // -----
    const COMMAND_TYPE_APPROVE_MESSAGES: u8 = 0;
    const COMMAND_TYPE_ROTATE_SIGNERS: u8 = 1;

    /// An object holding the state of the Axelar bridge.
    /// The central piece in managing call approval creation and signature verification.
    public struct Gateway has key {
        id: UID,
        approvals: Table<address, Approval>,  // TODO: remove
        messages: Table<vector<u8>, MessageStatus>,
        signers: AxelarSigners,
    }

    /// The Status of the message.
    /// Can be either one of three statuses:
    /// - Non-existent: Set to bytes32(0)
    /// - Approved: Set to the hash of the message
    /// - Executed: Set to bytes32(1)
    public struct MessageStatus has store {
        status: Bytes32,
    }

    /// CallApproval struct which can consumed only by a `Channel` object.
    /// Does not require additional generic field to operate as linking
    /// by `id_bytes` is more than enough.
    public struct Approval has store {
        /// Hash of the cmd_id, destination_id, source_chain, source_address, payload_hash
        approval_hash: vector<u8>,
    }

    // ------------
    // Capabilities
    // ------------
    public struct CreatorCap has key, store {
        id: UID
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

    /// Emitted when a new message is approved by the gateway.
    public struct MessageApproved has copy, drop {
        message: message::Message,
    }

    /// Init the module by giving a CreatorCap to the sender to allow a full `setup`.
    fun init(ctx: &mut TxContext) {
        let cap = CreatorCap {
            id: object::new(ctx),
        };

        transfer::transfer(cap, tx_context::sender(ctx));
    }

    /// Setup the module by creating a new Gateway object.
    public fun setup(
        cap: CreatorCap,
        domain_separator: Bytes32,
        minimum_rotation_delay: u64,
        initial_signers: WeightedSigners,
        ctx: &mut TxContext
    ) {
        let CreatorCap { id } = cap;
        id.delete();

        let gateway = Gateway {
            id: object::new(ctx),
            approvals: table::new(ctx),
            messages: table::new(ctx),
            signers: auth::setup(domain_separator, minimum_rotation_delay, initial_signers, ctx),
        };

        // Share the gateway object for anyone to use.
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

    public fun is_message_approved(
        self: &Gateway,
        source_chain: String,
        message_id: String,
        source_address: String,
        destination_id: address,
        payload_hash: Bytes32,
    ): bool {
        let message = message::new(
            source_chain,
            message_id,
            source_address,
            destination_id,
            payload_hash,
        );
        let command_id = hash::keccak256(&message.id());

        self.messages[command_id].status == message.hash()
    }

    public fun is_message_executed(
        self: &Gateway,
        source_chain: String,
        message_id: String,
    ): bool {
        let command_id = hash::keccak256(&message::message_to_command_id(
            source_chain,
            message_id,
        ));

        self.messages[command_id].status == bytes32::new(@0x1)
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
        proof_data: vector<u8>,
    ) {
        let messages = peel_messages(*&message_data);
        let proof = peel_proof(proof_data);

        let _ = self.signers.validate_proof(data_hash(COMMAND_TYPE_APPROVE_MESSAGES, message_data), proof);

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
        proof_data: vector<u8>,
    ) {
        let weighted_signers = peel_weighted_signers(new_signers_data);
        let proof = peel_proof(proof_data);

        let is_latest_signers = self.signers.validate_proof(data_hash(COMMAND_TYPE_ROTATE_SIGNERS, new_signers_data), proof);
        assert!(is_latest_signers, ENotLatestSigners);

        // This will fail if signers are duplicated
        self.signers.rotate_signers(weighted_signers);
    }

    /// -----------------
    /// Private Functions
    /// -----------------

    fun peel_messages(message_data: vector<u8>): vector<Message> {
        let mut bcs = bcs::new(message_data);

        let mut messages = vector::empty<Message>();
        let mut len = bcs.peel_vec_length();

        while (len > 0) {
            messages.push_back(message::peel(&mut bcs));

            len = len - 1;
        };

        assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);
        assert!(messages.length() > 0, EInvalidLength);

        messages
    }

    fun peel_weighted_signers(weighted_signers_data: vector<u8>): WeightedSigners {
        let mut bcs = bcs::new(weighted_signers_data);

        let weighted_signers = weighted_signers::peel(&mut bcs);

        assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);

        weighted_signers
    }

    fun peel_proof(proof_data: vector<u8>): Proof {
        let mut bcs = bcs::new(proof_data);

        let proof = proof::peel(&mut bcs);

        assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);

        proof
    }

    fun data_hash(command_type: u8, data: vector<u8>): Bytes32 {
        let mut typed_data = vector::singleton(command_type);
        typed_data.append(data);

        bytes32::from_bytes(hash::keccak256(&typed_data))
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
            MessageStatus { status: message.hash() }
        );

        sui::event::emit(MessageApproved {
            message: *message,
        });
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
}