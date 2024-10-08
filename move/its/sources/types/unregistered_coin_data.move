module its::unregistered_coin_data;

use sui::coin::{TreasuryCap, CoinMetadata};

// -----
// Types
// -----
public struct UnregisteredCoinData<phantom T> has store {
    treasury_cap: TreasuryCap<T>,
    coin_metadata: CoinMetadata<T>,
}

// -----------------
// Package Functions
// -----------------
public(package) fun new<T>(
    treasury_cap: TreasuryCap<T>,
    coin_metadata: CoinMetadata<T>,
): UnregisteredCoinData<T> {
    UnregisteredCoinData {
        treasury_cap,
        coin_metadata,
    }
}

public(package) fun destroy<T>(
    self: UnregisteredCoinData<T>,
): (TreasuryCap<T>, CoinMetadata<T>) {
    let UnregisteredCoinData { treasury_cap, coin_metadata } = self;
    (treasury_cap, coin_metadata)
}
