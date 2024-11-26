module gas_service::gas_service_v0;

use axelar_gateway::message_ticket::MessageTicket;
use gas_service::events;
use std::ascii::String;
use sui::address;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::hash::keccak256;
use sui::sui::SUI;
use version_control::version_control::VersionControl;

// -------
// Structs
// -------
public struct GasService_v0 has store {
    balance: Balance<SUI>,
    version_control: VersionControl,
}

// -----------------
// Package Functions
// -----------------
public(package) fun new(version_control: VersionControl): GasService_v0 {
    GasService_v0 {
        balance: balance::zero<SUI>(),
        version_control,
    }
}

public(package) fun version_control(self: &GasService_v0): &VersionControl {
    &self.version_control
}

public(package) fun pay_gas(
    self: &mut GasService_v0,
    message_ticket: &MessageTicket,
    coin: Coin<SUI>,
    refund_address: address,
    params: vector<u8>,
) {
    let coin_value = coin.value();
    self.put(coin);

    let payload_hash = address::from_bytes(
        keccak256(&message_ticket.payload()),
    );

    events::gas_paid<SUI>(
        message_ticket.source_id(),
        message_ticket.destination_chain(),
        message_ticket.destination_address(),
        payload_hash,
        coin_value,
        refund_address,
        params,
    );
}

public(package) fun add_gas(
    self: &mut GasService_v0,
    coin: Coin<SUI>,
    message_id: String,
    refund_address: address,
    params: vector<u8>,
) {
    let coin_value = coin.value();
    self.put(coin);

    events::gas_added<SUI>(
        message_id,
        coin_value,
        refund_address,
        params,
    );
}

public(package) fun collect_gas(
    self: &mut GasService_v0,
    receiver: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    transfer::public_transfer(
        self.take(amount, ctx),
        receiver,
    );

    events::gas_collected<SUI>(
        receiver,
        amount,
    );
}

public(package) fun refund(
    self: &mut GasService_v0,
    message_id: String,
    receiver: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    transfer::public_transfer(
        self.take(amount, ctx),
        receiver,
    );

    events::refunded<SUI>(
        message_id,
        amount,
        receiver,
    );
}

public(package) fun allow_function(
    self: &mut GasService_v0,
    version: u64,
    function_name: String,
) {
    self.version_control.allow_function(version, function_name);
}

public(package) fun disallow_function(
    self: &mut GasService_v0,
    version: u64,
    function_name: String,
) {
    self.version_control.disallow_function(version, function_name);
}

// -----------------
// Private Functions
// -----------------
fun put(self: &mut GasService_v0, coin: Coin<SUI>) {
    coin::put(&mut self.balance, coin);
}

fun take(
    self: &mut GasService_v0,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    coin::take(&mut self.balance, amount, ctx)
}

// ---------
// Test Only
// ---------
#[test_only]
public(package) fun version_control_mut(
    self: &mut GasService_v0,
): &mut VersionControl {
    &mut self.version_control
}

#[test_only]
public(package) fun balance(self: &GasService_v0): &Balance<SUI> {
    &self.balance
}

#[test_only]
public(package) fun balance_mut(self: &mut GasService_v0): &mut Balance<SUI> {
    &mut self.balance
}

#[test_only]
public(package) fun destroy_for_testing(self: GasService_v0) {
    let GasService_v0 { balance, version_control: _ } = self;
    balance.destroy_for_testing();
}
