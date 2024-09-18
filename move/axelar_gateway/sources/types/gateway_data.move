/// Implementation of the Axelar Gateway for Sui Move.
///
/// This code is based on the following:
///
/// - When call approvals is sent to Sui, it targets an object and not a module;
/// - To support cross-chain messaging, a Channel object has to be created;
/// - Channel can be either owned or shared but not frozen;
/// - Module developer on the Sui side will have to implement a system to support messaging;
/// - Checks for uniqueness of approvals should be done through `Channel`s to avoid big data storage;
///
/// I. Sending call approvals
///
/// A approval is sent through the `send` function, a Channel is supplied to determine the source -> ID.
/// Event is then emitted and Axelar network can operate
///
/// II. Receiving call approvals
///
/// Approval bytes and signatures are passed into `create` function to generate a CallApproval object.
///  - Signatures are checked against the known set of signers.
///  - CallApproval bytes are parsed to determine: source, destination_chain, payload and destination_id
///  - `destination_id` points to a `Channel` object
///
/// Once created, `CallApproval` needs to be consumed. And the only way to do it is by calling
/// `consume_call_approval` function and pass a correct `Channel` instance alongside the `CallApproval`.
///  - CallApproval is checked for uniqueness (for this channel)
///  - CallApproval is checked to match the `Channel`.id
///
module axelar_gateway::gateway_data;

use sui::table::{Self, Table};

use axelar_gateway::bytes32::Bytes32;
use axelar_gateway::auth::AxelarSigners;
use axelar_gateway::message_status::MessageStatus;

// -----
// Types
// -----
/// An object holding the state of the Axelar bridge.
/// The central piece in managing call approval creation and signature verification.
public struct GatewayDataV0 has store {
    operator: address,
    messages: Table<Bytes32, MessageStatus>,
    signers: AxelarSigners,
}



// -----------------
// Package Functions
// -----------------
/// Init the module by giving a CreatorCap to the sender to allow a full `setup`.
public (package) fun new(
    operator: address,
    messages: Table<Bytes32, MessageStatus>,
    signers: AxelarSigners,
): GatewayDataV0 {
    GatewayDataV0 {
        operator,
        messages,
        signers,
    }
}

public(package) fun operator(self: &GatewayDataV0): &address {
    &self.operator
}

public (package) fun operator_mut(self: &mut GatewayDataV0): &mut address {
    &mut self.operator
}

public (package) fun messages(self: &GatewayDataV0): &Table<Bytes32, MessageStatus> {
    &self.messages
}

public (package) fun messages_mut(self: &mut GatewayDataV0): &mut Table<Bytes32, MessageStatus> {
    &mut self.messages
}

public (package) fun signers(self: &GatewayDataV0): &AxelarSigners {
    &self.signers
}

public (package) fun signers_mut(self: &mut GatewayDataV0): &mut AxelarSigners {
    &mut self.signers
}

#[syntax(index)]
public fun borrow(self: &GatewayDataV0, command_id: Bytes32): &MessageStatus {
    table::borrow(&self.messages, command_id)
}

#[syntax(index)]
public fun borrow_mut(
    self: &mut GatewayDataV0,
    command_id: Bytes32,
): &mut MessageStatus {
    table::borrow_mut(&mut self.messages, command_id)
}

#[test_only]
public fun destroy_for_testing(self: GatewayDataV0): (
    address,
    Table<Bytes32, MessageStatus>,
    AxelarSigners,
) {
    let GatewayDataV0 {
        operator,
        messages,
        signers
    } = self;
    (
        operator,
        messages,
        signers,
    )
}

