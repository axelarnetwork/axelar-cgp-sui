module axelar_gateway::message {
    use std::ascii::String;
    use sui::bcs::{Self, BCS};
    use sui::address;
    use sui::hash;

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
    /// Public Functions
    /// -----------------
    public fun new(
        source_chain: String,
        message_id: String,
        source_address: String,
        destination_id: address,
        payload_hash: Bytes32,
    ): Message {
        Message {
            source_chain,
            message_id,
            source_address,
            destination_id,
            payload_hash,
        }
    }

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

    public(package) fun message_to_command_id(source_chain: String, message_id: String): vector<u8> {
        let mut id = source_chain.into_bytes();
        id.append(b"_");
        id.append(message_id.into_bytes());

        id
    }

    public(package) fun id(self: &Message): vector<u8> {
        message_to_command_id(self.source_chain, self.message_id)
    }

    public(package) fun hash(self: &Message): Bytes32 {
        bytes32::from_bytes(hash::keccak256(&bcs::to_bytes(self)))
    }
}
