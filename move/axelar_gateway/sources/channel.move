/// Channels
///
/// Channels allow sending and receiving messages between Sui and other chains.
/// A channel has a unique id and is treated as the destination address by the
/// Axelar protocol.
/// Apps can create a channel and hold on to it for cross-chain messaging.
module axelar_gateway::channel;

use axelar_gateway::events;
use std::ascii::String;

// -----
// Types
// -----

/// The Channel object. Acts as a destination for the messages sent through
/// the bridge. The `destination_id` is compared against the `id` of the
/// `Channel`
/// when the message is consumed
public struct Channel has key, store {
    /// Unique ID of the channel
    id: UID,
}

/// A HotPotato - this should be received by the application contract and
/// consumed
public struct ApprovedMessage {
    /// Source chain axelar-registered name
    source_chain: String,
    /// Unique ID of the message
    message_id: String,
    /// Address of the source chain, encoded as a string (e.g. EVM address will
    /// be hex string 0x1234...abcd)
    source_address: String,
    /// The destination Channel's UID
    destination_id: address,
    /// Message payload
    payload: vector<u8>,
}

// ------
// Errors
// ------

/// If approved message is consumed by an invalid destination id
#[error]
const EInvalidDestination: vector<u8> = b"invalid destination";

// ----------------
// Public Functions
// ----------------

/// Create new `Channel` object.
/// Anyone can create their own `Channel` to receive cross-chain messages.
/// In most use cases, a package should create this on init, and hold on to it
/// forever.
public fun new(ctx: &mut TxContext): Channel {
    let id = object::new(ctx);

    events::channel_created(id.uid_to_address());

    Channel {
        id,
    }
}

/// Destroy a `Channel`. Allows apps to destroy the `Channel` object when it's
/// no longer needed.
public fun destroy(self: Channel) {
    let Channel { id } = self;

    events::channel_destroyed(id.uid_to_address());

    id.delete();
}

public fun id(self: &Channel): ID {
    object::id(self)
}

public fun to_address(self: &Channel): address {
    object::id_address(self)
}

/// Consume an approved message hot potato object intended for this `Channel`.
public fun consume_approved_message(
    channel: &Channel,
    approved_message: ApprovedMessage,
): (String, String, String, vector<u8>) {
    let ApprovedMessage {
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    } = approved_message;

    // Check if the message is sent to the correct destination.
    assert!(destination_id == object::id_address(channel), EInvalidDestination);

    (source_chain, message_id, source_address, payload)
}

// -----------------
// Package Functions
// -----------------

/// Create a new `ApprovedMessage` object to be sent to another chain. Is called
/// by the gateway when a message is "picked up" by the relayer.
public(package) fun create_approved_message(
    source_chain: String,
    message_id: String,
    source_address: String,
    destination_id: address,
    payload: vector<u8>,
): ApprovedMessage {
    ApprovedMessage {
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    }
}

// ---------
// Test Only
// ---------
#[test_only]
public fun new_approved_message(
    source_chain: String,
    message_id: String,
    source_address: String,
    destination_id: address,
    payload: vector<u8>,
): ApprovedMessage {
    ApprovedMessage {
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    }
}

#[test_only]
public fun destroy_for_testing(approved_message: ApprovedMessage) {
    ApprovedMessage {
        source_chain: _,
        message_id: _,
        source_address: _,
        destination_id: _,
        payload: _,
    } = approved_message;
}

#[test_only]
public(package) fun approved_message_source_chain(
    self: &ApprovedMessage,
): String {
    self.source_chain
}

#[test_only]
public(package) fun approved_message_message_id(
    self: &ApprovedMessage,
): String {
    self.message_id
}

#[test_only]
public(package) fun approved_message_source_address(
    self: &ApprovedMessage,
): String {
    self.source_address
}

#[test_only]
public(package) fun approved_message_destination_id(
    self: &ApprovedMessage,
): address {
    self.destination_id
}

#[test_only]
public(package) fun approved_message_payload(
    self: &ApprovedMessage,
): vector<u8> {
    self.payload
}

// -----
// Tests
// -----
#[test]
fun test_new_and_destroy() {
    let ctx = &mut sui::tx_context::dummy();
    let channel: Channel = new(ctx);
    channel.destroy()
}

#[test]
fun test_id() {
    let ctx = &mut sui::tx_context::dummy();
    let channel: Channel = new(ctx);
    assert!(channel.id() == object::id(&channel));
    channel.destroy()
}

#[test]
fun test_to_address() {
    let ctx = &mut sui::tx_context::dummy();
    let channel: Channel = new(ctx);
    assert!(channel.to_address() == object::id_address(&channel));
    channel.destroy()
}

#[test]
fun test_create_approved_message() {
    let input_source_chain = std::ascii::string(b"Source Chain");
    let input_message_id = std::ascii::string(b"message id");
    let input_source_address = std::ascii::string(b"Source Address");
    let input_destination_id = @0x5678;
    let input_payload = b"payload";
    let approved_message: ApprovedMessage = create_approved_message(
        input_source_chain,
        input_message_id,
        input_source_address,
        input_destination_id,
        input_payload,
    );

    let ApprovedMessage {
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    } = approved_message;
    assert!(source_chain == input_source_chain);
    assert!(message_id == input_message_id);
    assert!(source_address == input_source_address);
    assert!(destination_id == input_destination_id);
    assert!(payload == input_payload);
}

#[test]
fun test_consume_approved_message() {
    let ctx = &mut sui::tx_context::dummy();
    let channel: Channel = new(ctx);

    let input_source_chain = std::ascii::string(b"Source Chain");
    let input_message_id = std::ascii::string(b"message id");
    let input_source_address = std::ascii::string(b"Source Address");
    let input_destination_id = channel.to_address();
    let input_payload = b"payload";
    let approved_message: ApprovedMessage = create_approved_message(
        input_source_chain,
        input_message_id,
        input_source_address,
        input_destination_id,
        input_payload,
    );

    let (
        source_chain,
        message_id,
        source_address,
        payload,
    ) = channel.consume_approved_message(approved_message);

    assert!(source_chain == input_source_chain);
    assert!(message_id == input_message_id);
    assert!(source_address == input_source_address);
    assert!(payload == input_payload);

    channel.destroy();
}

#[test]
#[expected_failure(abort_code = EInvalidDestination)]
fun test_consume_approved_message_wrong_destination() {
    let ctx = &mut sui::tx_context::dummy();
    let channel: Channel = new(ctx);

    let source_chain = std::ascii::string(b"Source Chain");
    let message_id = std::ascii::string(b"message id");
    let source_address = std::ascii::string(b"Source Address");
    let destination_id = @0x5678;
    let payload = b"payload";

    let approved_message = create_approved_message(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    );

    channel.consume_approved_message(approved_message);

    channel.destroy();
}
