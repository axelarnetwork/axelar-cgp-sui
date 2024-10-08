module its::coin_data;

use its::coin_info::CoinInfo;
use its::coin_management::CoinManagement;

// -----
// Types
// -----
public struct CoinData<phantom T> has store {
    coin_management: CoinManagement<T>,
    coin_info: CoinInfo<T>,
}

// -----------------
// Package Functions
// -----------------
public(package) fun new<T>(
    coin_management: CoinManagement<T>,
    coin_info: CoinInfo<T>,
): CoinData<T> {
    CoinData<T> {
        coin_management,
        coin_info,
    }
}

public(package) fun coin_info<T>(self: &CoinData<T>): &CoinInfo<T> {
    &self.coin_info
}

public(package) fun coin_management_mut<T>(
    self: &mut CoinData<T>,
): &mut CoinManagement<T> {
    &mut self.coin_management
}

public(package) fun coin_scaling<T>(self: &CoinData<T>): u256 {
    self.coin_info.scaling()
}
