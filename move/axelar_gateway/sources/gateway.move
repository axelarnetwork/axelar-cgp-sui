/// Implementation of the Axelar Gateway for Sui Move.
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
module axelar_gateway::gateway;

use axelar_gateway::auth::{Self, AxelarSigners, validate_proof};
use axelar_gateway::bytes32::{Self, Bytes32};
use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
use axelar_gateway::message::{Self, Message};
use axelar_gateway::proof::{Self, Proof};
use axelar_gateway::weighted_signers::{Self, WeightedSigners};
use std::ascii::String;
use sui::address;
use sui::bcs;
use sui::clock::Clock;
use sui::hash;
use sui::table::{Self, Table};
use version_control::version_control::{Self, VersionControl};

// ------
// Version
// ------
const VERSION: u64 = 0;

// ------
// Errors
// ------
/// Trying to `take_approved_message` for a message that is not approved.
const EMessageNotApproved: u64 = 0;
/// Invalid length of vector
const EInvalidLength: u64 = 1;
/// Remaining data after BCS decoding
const ERemainingData: u64 = 2;
/// Not latest signers
const ENotLatestSigners: u64 = 3;
/// MessageTickets created from newer versions cannot be sent here
const ENewerMessage: u64 = 4;

// -----
// Types
// -----
const COMMAND_TYPE_APPROVE_MESSAGES: u8 = 0;
const COMMAND_TYPE_ROTATE_SIGNERS: u8 = 1;

/// An object holding the state of the Axelar bridge.
/// The central piece in managing call approval creation and signature verification.
public struct Gateway has key {
    id: UID,
    operator: address,
    messages: Table<Bytes32, MessageStatus>,
    signers: AxelarSigners,
    version_control: VersionControl,
}

/// [docstring]
/// The version is captured to ensure that future packages can restrict which messages they can send, and to ensure that no future messages are sent from earlier versions.
public struct MessageTicket {
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    version: u64,
}

/// The Status of the message.
/// Can be either one of two statuses:
/// - Approved: Set to the hash of the message
/// - Executed: Message was already executed
public enum MessageStatus has copy, drop, store {
    Approved(Bytes32),
    Executed,
}

// ------------
// Capabilities
// ------------
public struct CreatorCap has key, store {
    id: UID,
}

// ------
// Events
// ------

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

/// Emitted when a message is taken to be executed by a channel.
public struct MessageExecuted has copy, drop {
    message: message::Message,
}

// -----
// Setup
// -----

/// Init the module by giving a CreatorCap to the sender to allow a full `setup`.
fun init(ctx: &mut TxContext) {
    let cap = CreatorCap {
        id: object::new(ctx),
    };

    transfer::transfer(cap, ctx.sender());
}

/// Setup the module by creating a new Gateway object.
public fun setup(
    cap: CreatorCap,
    operator: address,
    domain_separator: Bytes32,
    minimum_rotation_delay: u64,
    previous_signers_retention: u64,
    initial_signers: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let CreatorCap { id } = cap;
    id.delete();

    let gateway = Gateway {
        id: object::new(ctx),
        operator,
        messages: table::new(ctx),
        signers: auth::setup(
            domain_separator,
            minimum_rotation_delay,
            previous_signers_retention,
            peel_weighted_signers(initial_signers),
            clock,
            ctx,
        ),
        version_control: version_control(),
    };

    // Share the gateway object for anyone to use.
    transfer::share_object(gateway);
}

#[syntax(index)]
public fun borrow(self: &Gateway, command_id: Bytes32): &MessageStatus {
    table::borrow(&self.messages, command_id)
}

#[syntax(index)]
public fun borrow_mut(
    self: &mut Gateway,
    command_id: Bytes32,
): &mut MessageStatus {
    table::borrow_mut(&mut self.messages, command_id)
}

// -----------
// Entrypoints
// -----------

/// The main entrypoint for approving Axelar signed messages.
/// If proof is valid, message approvals are stored in the Gateway object, if not already approved before.
/// This method is only intended to be called via a Transaction Block, keeping more flexibility for upgrades.
entry fun approve_messages(
    self: &mut Gateway,
    message_data: vector<u8>,
    proof_data: vector<u8>,
) {
    self.version_control.check(VERSION, b"approve_messages");
    let messages = peel_messages(*&message_data);
    let proof = peel_proof(proof_data);

    let _ = self
        .signers
        .validate_proof(
            data_hash(COMMAND_TYPE_APPROVE_MESSAGES, message_data),
            proof,
        );

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
    clock: &Clock,
    new_signers_data: vector<u8>,
    proof_data: vector<u8>,
    ctx: &TxContext,
) {
    self.version_control.check(VERSION, b"rotate_signers");
    let weighted_signers = peel_weighted_signers(new_signers_data);
    let proof = peel_proof(proof_data);

    let enforce_rotation_delay = ctx.sender() != self.operator;

    let is_latest_signers = self
        .signers
        .validate_proof(
            data_hash(COMMAND_TYPE_ROTATE_SIGNERS, new_signers_data),
            proof,
        );
    assert!(!enforce_rotation_delay || is_latest_signers, ENotLatestSigners);

    // This will fail if signers are duplicated
    self
        .signers
        .rotate_signers(clock, weighted_signers, enforce_rotation_delay);
}

// ----------------
// Public Functions
// ----------------

/// Prepare a MessageTicket to call a contract on the destination chain.
public fun prepare_message(
    channel: &Channel,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
): MessageTicket {
    MessageTicket {
        source_id: channel.to_address(),
        destination_chain,
        destination_address,
        payload,
        version: VERSION,
    }
}

/// Submit the MessageTicket which causes a contract call by sending an event from an
/// authorized Channel.
public fun send_message(
    message: MessageTicket,
) {
    let MessageTicket {
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    } = message;
    assert!(version <= VERSION, ENewerMessage);
    sui::event::emit(ContractCall {
        source_id,
        destination_chain,
        destination_address,
        payload,
        payload_hash: address::from_bytes(hash::keccak256(&payload)),
    });
}

public fun is_message_approved(
    self: &Gateway,
    source_chain: String,
    message_id: String,
    source_address: String,
    destination_id: address,
    payload_hash: Bytes32,
): bool {
    self.version_control.check(VERSION, b"is_message_approved");
    let message = message::new(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload_hash,
    );
    let command_id = message.command_id();

    self[command_id] == MessageStatus::Approved(message.hash())
}

public fun is_message_executed(
    self: &Gateway,
    source_chain: String,
    message_id: String,
): bool {
    self.version_control.check(VERSION, b"is_message_executed");
    let command_id = message::message_to_command_id(
        source_chain,
        message_id,
    );

    self[command_id] == MessageStatus::Executed
}

/// To execute a message, the relayer will call `take_approved_message`
/// to get the hot potato `ApprovedMessage` object, and then trigger the app's package via discovery.
public fun take_approved_message(
    self: &mut Gateway,
    source_chain: String,
    message_id: String,
    source_address: String,
    destination_id: address,
    payload: vector<u8>,
): ApprovedMessage {
    self.version_control.check(VERSION, b"take_approved_message");
    let command_id = message::message_to_command_id(source_chain, message_id);

    let message = message::new(
        source_chain,
        message_id,
        source_address,
        destination_id,
        bytes32::from_bytes(hash::keccak256(&payload)),
    );

    assert!(
        self[command_id] == MessageStatus::Approved(message.hash()),
        EMessageNotApproved,
    );

    let message_status_ref = &mut self[command_id];
    *message_status_ref = MessageStatus::Executed;

    sui::event::emit(MessageExecuted {
        message,
    });

    // Friend only.
    channel::create_approved_message(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    )
}

// --------------
// Ticket Getters
// --------------
public fun source_id(self: &MessageTicket): address {
    self.source_id
}

public fun destination_chain(self: &MessageTicket): String {
    self.destination_chain
}

public fun destination_address(self: &MessageTicket): String {
    self.destination_address
}

public fun payload(self: &MessageTicket): vector<u8> {
    self.payload
}

public fun version(self: &MessageTicket): u64 {
    self.version
}

// -----------------
// Private Functions
// -----------------

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

fun approve_message(self: &mut Gateway, message: &message::Message) {
    let command_id = message.command_id();

    // If the message was already approved, ignore it.
    if (self.messages.contains(command_id)) {
        return
    };

    self
        .messages
        .add(
            command_id,
            MessageStatus::Approved(message.hash()),
        );

    sui::event::emit(MessageApproved {
        message: *message,
    });
}

fun version_control(): VersionControl {
    version_control::new(
        vector [
            vector [
                b"approve_messages",
                b"rotate_signers",
                b"is_message_approved",
                b"is_message_executed",
                b"take_approved_message",
            ]
        ]
    )
}

#[test_only]
public fun create_for_testing(
    operator: address,
    domain_separator: Bytes32,
    minimum_rotation_delay: u64,
    previous_signers_retention: u64,
    initial_signers: WeightedSigners,
    clock: &Clock,
    ctx: &mut TxContext,
): Gateway {
    Gateway {
        id: object::new(ctx),
        operator,
        messages: table::new(ctx),
        signers: auth::setup(
            domain_separator,
            minimum_rotation_delay,
            previous_signers_retention,
            initial_signers,
            clock,
            ctx,
        ),
        version_control: version_control(),
    }
}

#[test_only]
public fun dummy(ctx: &mut TxContext): Gateway {
    Gateway {
        id: object::new(ctx),
        operator: @0x0,
        messages: table::new(ctx),
        signers: auth::dummy(ctx),
        version_control: version_control(),
    }
}

#[test_only]
public fun destroy_for_testing(gateway: Gateway) {
    let Gateway {
        id,
        operator: _,
        messages,
        signers,
        version_control: _,
    } = gateway;

    id.delete();
    let (_, table, _, _, _, _) = signers.destroy_for_testing();
    table.destroy_empty();
    messages.destroy_empty();
}

#[test]
fun test_setup() {
    let ctx = &mut sui::tx_context::dummy();
    let operator = @123456;
    let domain_separator = bytes32::new(@789012);
    let minimum_rotation_delay = 765;
    let previous_signers_retention = 650;
    let initial_signers = axelar_gateway::weighted_signers::dummy();
    let mut clock = sui::clock::create_for_testing(ctx);
    let timestamp = 1234;
    clock.increment_for_testing(timestamp);

    let creator_cap = CreatorCap {
        id: object::new(ctx),
    };

    let mut scenario = sui::test_scenario::begin(@0x1);

    setup(
        creator_cap,
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        bcs::to_bytes(&initial_signers),
        &clock,
        scenario.ctx(),
    );

    let tx_effects = scenario.next_tx(@0x1);
    let shared = tx_effects.shared();

    assert!(shared.length() == 1, 0);

    let gateway_id = shared[0];
    let gateway = scenario.take_shared_by_id<Gateway>(gateway_id);

    let Gateway {
        id,
        operator: operator_result,
        messages,
        signers,
        version_control: _,
    } = { gateway };

    id.delete();
    assert!(operator == operator_result, 1);
    messages.destroy_empty();

    let (
        epoch,
        mut epoch_by_signers_hash,
        domain_separator_result,
        minimum_rotation_delay_result,
        last_rotation_timestamp,
        previous_signers_retention_result,
    ) = signers.destroy_for_testing();

    let signer_epoch = epoch_by_signers_hash.remove(initial_signers.hash());
    epoch_by_signers_hash.destroy_empty();

    assert!(epoch == 1, 2);
    assert!(signer_epoch == 1, 3);
    assert!(domain_separator == domain_separator_result, 4);
    assert!(minimum_rotation_delay == minimum_rotation_delay_result, 5);
    assert!(last_rotation_timestamp == timestamp, 6);
    assert!(previous_signers_retention == previous_signers_retention_result, 7);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_approve_message() {
    let ctx = &mut sui::tx_context::dummy();

    let message_id = std::ascii::string(b"Message Id");
    let channel = axelar_gateway::channel::new(ctx);
    let source_chain = std::ascii::string(b"Source Chain");
    let source_address = std::ascii::string(b"Destination Address");
    let payload = vector[0, 1, 2, 3];
    let payload_hash = axelar_gateway::bytes32::new(
        address::from_bytes(hash::keccak256(&payload)),
    );

    let message = message::new(
        source_chain,
        message_id,
        source_address,
        channel.to_address(),
        payload_hash,
    );

    let mut gateway = dummy(ctx);

    approve_message(&mut gateway, &message);
    // The second approve message should do nothing.
    approve_message(&mut gateway, &message);

    assert!(
        is_message_approved(
            &gateway,
            source_chain,
            message_id,
            source_address,
            channel.to_address(),
            payload_hash,
        ) ==
        true,
        0,
    );

    let approved_message = take_approved_message(
        &mut gateway,
        source_chain,
        message_id,
        source_address,
        channel.to_address(),
        payload,
    );

    channel.consume_approved_message(approved_message);

    assert!(
        is_message_approved(
            &gateway,
            source_chain,
            message_id,
            source_address,
            channel.to_address(),
            payload_hash,
        ) ==
        false,
        1,
    );

    assert!(
        is_message_executed(
            &gateway,
            source_chain,
            message_id,
        ) ==
        true,
        2,
    );

    gateway.messages.remove(message.command_id());

    gateway.destroy_for_testing();
    channel.destroy();
}

#[test]
fun test_peel_messages() {
    let message1 = message::new(
        std::ascii::string(b"Source Chain 1"),
        std::ascii::string(b"Message Id 1"),
        std::ascii::string(b"Source Address 1"),
        @0x1,
        axelar_gateway::bytes32::new(@0x2),
    );

    let message2 = message::new(
        std::ascii::string(b"Source Chain 2"),
        std::ascii::string(b"Message Id 2"),
        std::ascii::string(b"Source Address 2"),
        @0x3,
        axelar_gateway::bytes32::new(@0x4),
    );

    let bytes = bcs::to_bytes(&vector[message1, message2]);

    let messages = peel_messages(bytes);

    assert!(messages.length() == 2, 0);
    assert!(messages[0] == message1, 1);
    assert!(messages[1] == message2, 2);
}

#[test]
#[expected_failure(abort_code = ERemainingData)]
fun test_peel_messages_no_remaining_data() {
    let message1 = message::new(
        std::ascii::string(b"Source Chain 1"),
        std::ascii::string(b"Message Id 1"),
        std::ascii::string(b"Source Address 1"),
        @0x1,
        axelar_gateway::bytes32::new(@0x2),
    );

    let mut bytes = bcs::to_bytes(&vector[message1]);
    bytes.push_back(0);

    peel_messages(bytes);
}

#[test]
#[expected_failure(abort_code = EInvalidLength)]
fun test_peel_messages_no_zero_messages() {
    peel_messages(bcs::to_bytes(&vector<Message>[]));
}

#[test]
fun test_peel_weighted_signers() {
    let signers = axelar_gateway::weighted_signers::dummy();
    let bytes = bcs::to_bytes(&signers);
    let result = peel_weighted_signers(bytes);

    assert!(result == signers, 0);
}

#[test]
#[expected_failure(abort_code = ERemainingData)]
fun test_peel_weighted_signers_no_remaining_data() {
    let signers = axelar_gateway::weighted_signers::dummy();
    let mut bytes = bcs::to_bytes(&signers);
    bytes.push_back(0);

    peel_weighted_signers(bytes);
}

#[test]
fun test_peel_proof() {
    let proof = axelar_gateway::proof::dummy();
    let bytes = bcs::to_bytes(&proof);
    let result = peel_proof(bytes);

    assert!(result == proof, 0);
}

#[test]
#[expected_failure(abort_code = ERemainingData)]
fun test_peel_proof_no_remaining_data() {
    let proof = axelar_gateway::proof::dummy();
    let mut bytes = bcs::to_bytes(&proof);
    bytes.push_back(0);

    peel_proof(bytes);
}

#[test]
#[expected_failure(abort_code = EMessageNotApproved)]
fun test_take_approved_message_message_not_approved() {
    let mut gateway = dummy(&mut sui::tx_context::dummy());

    let message = message::new(
        std::ascii::string(b"Source Chain"),
        std::ascii::string(b"Message Id"),
        std::ascii::string(b"Source Address"),
        @0x1,
        axelar_gateway::bytes32::new(@0x2),
    );

    gateway
        .messages
        .add(
            message.command_id(),
            MessageStatus::Approved(axelar_gateway::bytes32::new(@0x3)),
        );

    let approved_message = take_approved_message(
        &mut gateway,
        std::ascii::string(b"Source Chain"),
        std::ascii::string(b"Message Id"),
        std::ascii::string(b"Source Address"),
        @0x12,
        vector[0, 1, 2],
    );

    gateway.messages.remove(message.command_id());

    approved_message.destroy_for_testing();
    gateway.destroy_for_testing();
}

#[test]
fun test_data_hash() {
    let command_type = 5;
    let data = vector[0, 1, 2, 3];
    let mut typed_data = vector::singleton(command_type);
    typed_data.append(data);

    assert!(
        data_hash(command_type, data) ==
        bytes32::from_bytes(hash::keccak256(&typed_data)),
        0,
    );
}
