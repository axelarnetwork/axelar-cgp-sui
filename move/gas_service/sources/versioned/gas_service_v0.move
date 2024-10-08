module gas_service::gas_service_v0;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
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

public(package) fun put(self: &mut GasService_v0, coin: Coin<SUI>) {
    coin::put(&mut self.balance, coin);
}

public(package) fun take(
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
public fun version_control_mut(self: &mut GasService_v0): &mut VersionControl {
    &mut self.version_control
}

#[test_only]
public fun balance(self: &GasService_v0): &Balance<SUI> {
    &self.balance
}

#[test_only]
public fun balance_mut(self: &mut GasService_v0): &mut Balance<SUI> {
    &mut self.balance
}

#[test_only]
public fun destroy_for_testing(self: GasService_v0) {
    let GasService_v0 { balance, version_control: _ } = self;
    balance.destroy_for_testing();
}
