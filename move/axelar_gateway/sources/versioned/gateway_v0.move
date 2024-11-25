module axelar_gateway::gateway_v0;

use axelar_gateway::auth::AxelarSigners;
use axelar_gateway::bytes32::Bytes32;
use axelar_gateway::message_status::MessageStatus;
use sui::table::Table;
use version_control::version_control::VersionControl;
use axelar_gateway::gateway_v1::{Self, Gateway_v1};

// -----
// Types
// -----
/// An object holding the state of the Axelar bridge.
/// The central piece in managing call approval creation and signature
/// verification.
public struct Gateway_v0 has store {
    operator: address,
    messages: Table<Bytes32, MessageStatus>,
    signers: AxelarSigners,
    version_control: VersionControl,
}

public enum CommandType {
    ApproveMessages,
    RotateSigners,
}

// -----------------
// Package Functions
// -----------------
public(package) fun migrate(self: Gateway_v0, version_control: VersionControl): Gateway_v1 {
    let Gateway_v0 {
        operator,
        messages,
        signers,
        version_control: _,
    } = self;
    gateway_v1::new(
        operator,
        messages,
        signers,
        version_control,
    )
}
