module gas_service::gas_service_v0;

use sui::balance::{Self, Balance};
use sui::sui::SUI;

// -----
// Types
// -----
public struct GasServiceV0 has store {
    balance: Balance<SUI>,
}

public (package) fun new(): GasServiceV0 {
    GasServiceV0 {
        balance: balance::zero<SUI>(),
    }
}

public(package) fun balance(self: &GasServiceV0): &Balance<SUI> {
    &self.balance
}

public (package) fun balance_mut(self: &mut GasServiceV0): &mut Balance<SUI> {
    &mut self.balance
}

#[test_only]
public fun destroy_for_testing(self: GasServiceV0) {
    let GasServiceV0 { balance } = self;
    balance.destroy_for_testing();
}
