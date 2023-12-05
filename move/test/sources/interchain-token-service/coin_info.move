module interchain_token_service::coin_info {
    use std::string;
    use std::ascii::{String};
    use std::option::{Self, Option};

    use sui::coin::{Self, CoinMetadata};

    struct CoinInfo<phantom T> has store {
        name: string::String,
        symbol: String,
        decimals: u8,
        metadata: Option<CoinMetadata<T>>,
    }
    
    public fun from_info<T>(name: string::String, symbol: String, decimals: u8): CoinInfo<T> {
        CoinInfo {
            name,
            symbol,
            decimals,
            metadata: option::none<CoinMetadata<T>>(),
        }
    }

    public fun from_metadata<T>(metadata: CoinMetadata<T>): CoinInfo<T> {
        let name = coin::get_name(&metadata);
        let symbol = coin::get_symbol(&metadata);
        let decimals = coin::get_decimals(&metadata);
        CoinInfo {
            name,
            symbol,
            decimals,
            metadata: option::some<CoinMetadata<T>>(metadata),
        }
    }

    public fun name<T>(self: &CoinInfo<T>): string::String {
        self.name
    }

    public fun symbol<T>(self: &CoinInfo<T>): String {
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
        let CoinInfo {name: _, symbol: _, decimals: _, metadata: _} = coin_info;
    }
} 