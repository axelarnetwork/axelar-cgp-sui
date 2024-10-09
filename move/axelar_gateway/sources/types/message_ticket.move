module axelar_gateway::message_ticket;

use std::ascii::String;

// -----
// Types
// -----
/// This hot potato object is created to capture all the information about a
/// remote contract call.
/// In can then be submitted to the gateway to send the Message.
/// It is advised that modules return this Message ticket to be submitted by the
/// frontend, so that when the gateway package is upgraded, the app doesn't need
/// to upgrade as well, ensuring forward compatibility.
/// The version is captured to ensure that future packages can restrict which
/// messages they can send, and to ensure that no future messages are sent from
/// earlier versions.
public struct MessageTicket {
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    version: u64,
}

// -------
// Getters
// -------
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
// Package Functions
// -----------------
public(package) fun new(
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    version: u64,
): MessageTicket {
    MessageTicket {
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    }
}

public(package) fun destroy(
    self: MessageTicket,
): (address, String, String, vector<u8>, u64) {
    let MessageTicket {
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    } = self;
    (source_id, destination_chain, destination_address, payload, version)
}

#[test_only]
public fun new_for_testing(
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    version: u64,
): MessageTicket {
    MessageTicket {
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    }
}

#[test]
fun test_all() {
    let source_id: address = @0x123;
    let destination_chain: String = std::ascii::string(b"Destination Chain");
    let destination_address: String = std::ascii::string(
        b"Destination Address",
    );
    let payload: vector<u8> = b"payload";
    let version: u64 = 2;

    let message_ticket = new(
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    );

    assert!(message_ticket.source_id() == source_id);
    assert!(message_ticket.destination_chain() == destination_chain);
    assert!(message_ticket.destination_address() == destination_address);
    assert!(message_ticket.payload() == payload);
    assert!(message_ticket.version() == version);

    let (
        result_source_id,
        result_destination_chain,
        result_destination_address,
        result_payload,
        result_version,
    ) = message_ticket.destroy();

    assert!(result_source_id == source_id);
    assert!(result_destination_chain == destination_chain);
    assert!(result_destination_address == destination_address);
    assert!(result_payload == payload);
    assert!(result_version == version);
}
