module axelar_gateway::message {
    use std::ascii::String;
    use sui::bcs::BCS;
    use sui::address;

    use axelar_gateway::bytes32::{Self, Bytes32};

    /// -----
    /// Types
    /// -----
    /// Cross chain message type
    public struct Message has copy, drop, store {
        source_chain: String,
        message_id: String,
        source_address: String,
        destination_id: address,
        payload_hash: Bytes32,
    }

    /// ------
    /// Errors
    /// ------
    /// Invalid bytes length
    const EInvalidLength: u64 = 0;

    /// -----------------
    /// Package Functions
    /// -----------------
    public(package) fun peel(bcs: &mut BCS): Message {
        // TODO: allow UTF-8 strings? Or keep it as more generic bytes?
        let source_chain = bcs.peel_vec_u8().to_ascii_string();
        let message_id = bcs.peel_vec_u8().to_ascii_string();
        let source_address = bcs.peel_vec_u8().to_ascii_string();

        let destination_id_bytes = bcs.peel_vec_u8();
        assert!(destination_id_bytes.length() == 32, EInvalidLength);

        let payload_hash = bytes32::peel(bcs);

        Message {
            source_chain,
            message_id,
            source_address,
            destination_id: address::from_bytes(destination_id_bytes),
            payload_hash,
        }
    }

    public(package) fun id(self: &Message): vector<u8> {
        let mut id = self.source_chain.into_bytes();
        id.append(b"_");
        id.append(self.message_id.into_bytes());

        id
    }
}
