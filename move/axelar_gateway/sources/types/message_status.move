module axelar_gateway::message_status;

use axelar_gateway::bytes32::Bytes32;

// -----
// Types
// -----
/// The Status of the message.
/// Can be either one of two statuses:
/// - Approved: Set to the hash of the message
/// - Executed: Message was already executed
public enum MessageStatus has copy, drop, store {
    Approved(Bytes32),
    Executed,
}

// -----------------
// Package Functions
// -----------------
public(package) fun approved(hash: Bytes32): MessageStatus {
    MessageStatus::Approved(hash)
}

public(package) fun executed(): MessageStatus {
    MessageStatus::Executed
}
