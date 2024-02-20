

/// Defines the `CoinInfo` type which allows to store information about a coin:
/// either derived from `CoinMetadata` or manually provided.
module its::coin_info {
    use std::ascii;
    use std::string::String;
    use std::option::{Self, Option};

    use sui::coin::{Self, CoinMetadata};

    public struct CoinInfo<phantom T> has store {
        name: String,
        symbol: ascii::String,
        decimals: u8,
        metadata: Option<CoinMetadata<T>>,
    }

    /// Create a new coin info from the given name, symbol and decimals.
    public fun from_info<T>(
        name: String, symbol: ascii::String, decimals: u8
    ): CoinInfo<T> {
        CoinInfo {
            name,
            symbol,
            decimals,
            metadata: option::none(),
        }
    }

    /// Create a new coin info from the given `CoinMetadata` object.
    public fun from_metadata<T>(metadata: CoinMetadata<T>): CoinInfo<T> {
        CoinInfo {
            name: coin::get_name(&metadata),
            symbol: coin::get_symbol(&metadata),
            decimals: coin::get_decimals(&metadata),
            metadata: option::some(metadata),
        }
    }

    // === Views ===

    public fun name<T>(self: &CoinInfo<T>): String {
        self.name
    }

    public fun symbol<T>(self: &CoinInfo<T>): ascii::String {
        self.symbol
    }

    public fun decimals<T>(self: &CoinInfo<T>): u8 {
        self.decimals
    }

    public fun metadata<T>(self: &CoinInfo<T>): &Option<CoinMetadata<T>> {
        &self.metadata
    }

    #[test_only]
    public fun drop<T>(coin_info: CoinInfo<T>) {
        let CoinInfo {name: _, symbol: _, decimals: _, metadata } = coin_info;
        if (option::is_some(&metadata)) {
            abort 0
        } else {
            option::destroy_none(metadata)
        }
    }
}
