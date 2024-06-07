module axelar_gateway::message {
    use std::ascii::String;
    use sui::bcs::{Self, BCS};
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
        let destination_id = bcs.peel_address();
        let payload_hash = bytes32::peel(bcs);

        Message {
            source_chain,
            message_id,
            source_address,
            destination_id,
            payload_hash,
        }
    }

    public(package) fun message_to_command_id(source_chain: String, message_id: String): Bytes32 {
        let mut id = source_chain.into_bytes();
        id.append(b"_");
        id.append(message_id.into_bytes());

        bytes32::from_bytes(hash::keccak256(&id))
    }

    public(package) fun command_id(self: &Message): Bytes32 {
        message_to_command_id(self.source_chain, self.message_id)
    }

    public(package) fun hash(self: &Message): Bytes32 {
        bytes32::from_bytes(hash::keccak256(&bcs::to_bytes(self)))
    }
}
