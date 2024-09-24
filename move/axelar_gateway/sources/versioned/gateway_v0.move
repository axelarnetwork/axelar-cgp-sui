module axelar_gateway::gateway_v0;

use std::ascii::String;

use sui::clock::Clock;
use sui::hash;
use sui::table::{Self, Table};
use sui::address;

use utils::utils;

use version_control::version_control::VersionControl;

use axelar_gateway::auth::AxelarSigners;
use axelar_gateway::bytes32::{Self, Bytes32};
use axelar_gateway::channel::{Self, ApprovedMessage};
use axelar_gateway::message::{Self, Message};
use axelar_gateway::message_status::{Self, MessageStatus};
use axelar_gateway::proof;
use axelar_gateway::weighted_signers;
use axelar_gateway::message_ticket::MessageTicket;
use axelar_gateway::events;

// ------
// Errors
// ------
#[error]
const EMessageNotApproved: vector<u8> = b"trying to `take_approved_message` for a message that is not approved";

#[error]
const EZeroMessages: vector<u8> = b"no mesages found";

#[error]
const ENotLatestSigners: vector<u8> = b"not latest signers";

#[error]
const ENewerMessage: vector<u8> = b"message ticket created from newer versions cannot be sent here";

// ---------
// CONSTANTS
// ---------
const COMMAND_TYPE_APPROVE_MESSAGES: u8 = 0;
const COMMAND_TYPE_ROTATE_SIGNERS: u8 = 1;

// -----
// Types
// -----
/// An object holding the state of the Axelar bridge.
/// The central piece in managing call approval creation and signature verification.
public struct GatewayV0 has store {
    operator: address,
    messages: Table<Bytes32, MessageStatus>,
    signers: AxelarSigners,
    version_control: VersionControl,
}

// -----------------
// Package Functions
// -----------------
/// Init the module by giving a CreatorCap to the sender to allow a full `setup`.
public(package) fun new(
    operator: address,
    messages: Table<Bytes32, MessageStatus>,
    signers: AxelarSigners,
    version_control: VersionControl,
): GatewayV0 {
    GatewayV0 {
        operator,
        messages,
        signers,
        version_control,
    }
}

public(package) fun version_control(self: &GatewayV0): &VersionControl {
    &self.version_control
}

#[syntax(index)]
public fun borrow(self: &GatewayV0, command_id: Bytes32): &MessageStatus {
    table::borrow(&self.messages, command_id)
}

#[syntax(index)]
public fun borrow_mut(
    self: &mut GatewayV0,
    command_id: Bytes32,
): &mut MessageStatus {
    table::borrow_mut(&mut self.messages, command_id)
}

public(package) fun approve_messages(
    self: &mut GatewayV0,
    message_data: vector<u8>,
    proof_data: vector<u8>,
) {
    let proof = utils::peel!(proof_data, |bcs| proof::peel(bcs));
    let messages = peel_messages(message_data);

    let _ = self
        .signers
        .validate_proof(
            data_hash(COMMAND_TYPE_APPROVE_MESSAGES, message_data),
            proof,
        );

    messages.do!(|message| self.approve_message(message));
}

public(package) fun rotate_signers(
    self: &mut GatewayV0,
    clock: &Clock,
    new_signers_data: vector<u8>,
    proof_data: vector<u8>,
    ctx: &TxContext,
) {
    let weighted_signers = utils::peel!(
        new_signers_data,
        |bcs| weighted_signers::peel(bcs),
    );
    let proof = utils::peel!(proof_data, |bcs| proof::peel(bcs));

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

public(package) fun is_message_approved(
    self: &GatewayV0,
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
    let command_id = message.command_id();

    self[command_id] == message_status::approved(message.hash())
}

public(package) fun is_message_executed(
    self: &GatewayV0,
    source_chain: String,
    message_id: String,
): bool {
    let command_id = message::message_to_command_id(
        source_chain,
        message_id,
    );

    self[command_id] == message_status::executed()
}

/// To execute a message, the relayer will call `take_approved_message`
/// to get the hot potato `ApprovedMessage` object, and then trigger the app's package via discovery.
public(package) fun take_approved_message(
    self: &mut GatewayV0,
    source_chain: String,
    message_id: String,
    source_address: String,
    destination_id: address,
    payload: vector<u8>,
): ApprovedMessage {
    let command_id = message::message_to_command_id(source_chain, message_id);

    let message = message::new(
        source_chain,
        message_id,
        source_address,
        destination_id,
        bytes32::from_bytes(hash::keccak256(&payload)),
    );

    assert!(
        self[command_id] == message_status::approved(message.hash()),
        EMessageNotApproved,
    );

    let message_status_ref = &mut self[command_id];
    *message_status_ref = message_status::executed();

    events::emit_message_executed(
        message,
    );

    // Friend only.
    channel::create_approved_message(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    )
}

public(package) fun send_message(_self: &GatewayV0, message: MessageTicket, current_version: u64) {
    let (
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    ) = message.destroy();
    assert!(version <= current_version, ENewerMessage);
    events::emit_contract_call(
        source_id,
        destination_chain,
        destination_address,
        payload,
        address::from_bytes(hash::keccak256(&payload)),
    );
}

// -----------------
// Private Functions
// -----------------

fun peel_messages(message_data: vector<u8>): vector<Message> {
    utils::peel!(
        message_data,
        |bcs| {
            let messages = vector::tabulate!(
                bcs.peel_vec_length(),
                |_| message::peel(bcs),
            );
            assert!(messages.length() > 0, EZeroMessages);
            messages
        },
    )
}

fun data_hash(command_type: u8, data: vector<u8>): Bytes32 {
    let mut typed_data = vector::singleton(command_type);
    typed_data.append(data);

    bytes32::from_bytes(hash::keccak256(&typed_data))
}

fun approve_message(self: &mut GatewayV0, message: message::Message) {
    let command_id = message.command_id();

    // If the message was already approved, ignore it.
    if (self.messages.contains(command_id)) {
        return
    };

    self
        .messages
        .add(
            command_id,
            message_status::approved(message.hash()),
        );

    events::emit_message_approved(
        message,
    );
}

/// ---------
/// Test Only
/// ---------

#[test_only]
public fun operator(self: &GatewayV0): &address {
    &self.operator
}

#[test_only]
public fun operator_mut(self: &mut GatewayV0): &mut address {
    &mut self.operator
}

#[test_only]
public fun messages(self: &GatewayV0): &Table<Bytes32, MessageStatus> {
    &self.messages
}

#[test_only]
public fun messages_mut(
    self: &mut GatewayV0,
): &mut Table<Bytes32, MessageStatus> {
    &mut self.messages
}

#[test_only]
public fun signers(self: &GatewayV0): &AxelarSigners {
    &self.signers
}

#[test_only]
public fun signers_mut(self: &mut GatewayV0): &mut AxelarSigners {
    &mut self.signers
}

#[test_only]
public fun version_control_mut(
    self: &mut GatewayV0,
): &mut VersionControl {
    &mut self.version_control
}

public fun destroy_for_testing(
    self: GatewayV0,
): (address, Table<Bytes32, MessageStatus>, AxelarSigners, VersionControl) {
    let GatewayV0 {
        operator,
        messages,
        signers,
        version_control,
    } = self;
    (operator, messages, signers, version_control)
}

#[test_only]
public fun dummy(ctx: &mut TxContext): GatewayV0 {
    new(
        @0x0,
        sui::table::new(ctx),
        axelar_gateway::auth::dummy(ctx),
        version_control::version_control::new(vector[]),
    )
}

#[test]
#[expected_failure(abort_code = EZeroMessages)]
fun test_peel_messages_no_zero_messages() {
    peel_messages(sui::bcs::to_bytes(&vector<Message>[]));
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
        sui::address::from_bytes(hash::keccak256(&payload)),
    );

    let message = message::new(
        source_chain,
        message_id,
        source_address,
        channel.to_address(),
        payload_hash,
    );

    let mut data = dummy(ctx);

    data.approve_message(message);
    // The second approve message should do nothing.
    data.approve_message(message);

    assert!(
        data.is_message_approved(
            source_chain,
            message_id,
            source_address,
            channel.to_address(),
            payload_hash,
        ) ==
        true,
        0,
    );

    let approved_message = data.take_approved_message(
        source_chain,
        message_id,
        source_address,
        channel.to_address(),
        payload,
    );

    channel.consume_approved_message(approved_message);

    assert!(
        data.is_message_approved(
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
        data.is_message_executed(
            source_chain,
            message_id,
        ) ==
        true,
        2,
    );

    data.messages.remove(message.command_id());

    sui::test_utils::destroy(data);
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

    let bytes = sui::bcs::to_bytes(&vector[message1, message2]);

    let messages = peel_messages(bytes);

    assert!(messages.length() == 2, 0);
    assert!(messages[0] == message1, 1);
    assert!(messages[1] == message2, 2);
}

#[test]
#[expected_failure]
fun test_peel_messages_no_remaining_data() {
    let message1 = message::new(
        std::ascii::string(b"Source Chain 1"),
        std::ascii::string(b"Message Id 1"),
        std::ascii::string(b"Source Address 1"),
        @0x1,
        axelar_gateway::bytes32::new(@0x2),
    );

    let mut bytes = sui::bcs::to_bytes(&vector[message1]);
    bytes.push_back(0);

    peel_messages(bytes);
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
