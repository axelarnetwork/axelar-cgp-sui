module gas_service::gas_service_data;

use sui::balance::{Self, Balance};
use sui::sui::SUI;

// -----
// Types
// -----
public struct GasServiceDataV0 has store {
    balance: Balance<SUI>,
}

public (package) fun new(): GasServiceDataV0 {
    GasServiceDataV0 {
        balance: balance::zero<SUI>(),
    }
}

public (package) fun balance(self: &GasServiceDataV0): &Balance<SUI> {
    &self.balance
}

public (package) fun balance_mut(self: &mut GasServiceDataV0): &mut Balance<SUI> {
    &mut self.balance
}

#[test_only]
public fun destroy_for_testing(self: GasServiceDataV0) {
    let GasServiceDataV0 { balance } = self;
    balance.destroy_for_testing();
}