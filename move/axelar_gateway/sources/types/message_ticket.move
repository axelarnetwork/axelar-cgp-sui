module axelar_gateway::message_ticket;

use std::ascii::String;

public struct MessageTicket {
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    version: u64,
}

public (package) fun new(
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

public (package) fun destroy(self: MessageTicket): () {
    let MessageTicket {
        source_id: _,
        destination_chain: _,
        destination_address: _,
        payload: _,
        version: _,
    } = self;
}

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