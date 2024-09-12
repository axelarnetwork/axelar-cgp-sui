module axelar_gateway::message_ticket;

use std::ascii::String;



// -----
// Types
// -----
/// The version is captured to ensure that future packages can restrict which messages they can send, and to ensure that no future messages are sent from earlier versions.
public struct Message {
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    version: u64,
}

// -------
// Getters
// -------
public fun source_id(self: &Message): address {
    self.source_id
}

public fun destination_chain(self: &Message): String {
    self.destination_chain
}

public fun destination_address(self: &Message): String {
    self.destination_address
}

public fun payload(self: &Message): vector<u8> {
    self.payload
}

public fun version(self: &Message): u64 {
    self.version
}

// ------
// Friend
// ------
public (package) fun new(
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    version: u64,
): Message {
    Message {
        source_id,
        destination_chain,
        destination_address,
        payload,
        version
    }
}

public (package) fun destroy(self: Message): (
    address, String, String, vector<u8>, u64,
) {
    let Message {
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    } = self;
    (
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    )
}