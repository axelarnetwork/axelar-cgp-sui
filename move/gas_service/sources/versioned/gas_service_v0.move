module gas_service::gas_service_v0;

use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::coin::{Self, Coin};

use version_control::version_control::VersionControl;

// -----
// Types
// -----
public struct GasServiceV0 has store {
    balance: Balance<SUI>,
    version_control: VersionControl,
}

public(package) fun new(version_control: VersionControl): GasServiceV0 {
    GasServiceV0 {
        balance: balance::zero<SUI>(),
        version_control,
    }
}

public(package) fun version_control(self: &GasServiceV0): &VersionControl {
    &self.version_control
}

public(package) fun put(self: &mut GasServiceV0, coin: Coin<SUI>) {
    coin::put(&mut self.balance, coin);
}

public(package) fun take(self: &mut GasServiceV0, amount: u64, ctx: &mut TxContext): Coin<SUI> {
    coin::take(&mut self.balance, amount, ctx)
}

#[test_only]
public fun version_control_mut(self: &mut GasServiceV0): &mut VersionControl {
    &mut self.version_control
}

#[test_only]
public fun balance(self: &GasServiceV0): &Balance<SUI> {
    &self.balance
}

#[test_only]
public fun balance_mut(self: &mut GasServiceV0): &mut Balance<SUI> {
    &mut self.balance
}

#[test_only]
public fun destroy_for_testing(self: GasServiceV0) {
    let GasServiceV0 { balance, version_control: _ } = self;
    balance.destroy_for_testing();
}
