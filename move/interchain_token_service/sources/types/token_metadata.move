/// Defines the `TokenMetadata` type which allows to store information metadata a token.
/// This type is like `CoinInfo` but doesn't allow storing the `CoinMetadata`
module interchain_token_service::token_metadata {
    use interchain_token_service::coin_info::{Self, CoinInfo};
    use std::{ascii, string::String};
    use sui::coin::CoinMetadata;

    public struct TokenMetadata<phantom T> has store {
        name: String,
        symbol: ascii::String,
        decimals: u8,
    }

    /// Create a token metadata from the given name, symbol and decimals.
    public fun from_info<T>(name: String, symbol: ascii::String, decimals: u8): TokenMetadata<T> {
        TokenMetadata {
            name,
            symbol,
            decimals,
        }
    }

    /// Create a token metadata from the given `CoinMetadata` object
    public fun from_metadata<T>(metadata: &CoinMetadata<T>): TokenMetadata<T> {
        TokenMetadata {
            name: metadata.get_name(),
            symbol: metadata.get_symbol(),
            decimals: metadata.get_decimals(),
        }
    }

    /// Create a token metadata from the given `CoinInfo` object
    public fun from_coin_info<T>(coin_info: &CoinInfo<T>): TokenMetadata<T> {
        TokenMetadata {
            name: coin_info.name(),
            symbol: coin_info.symbol(),
            decimals: coin_info.decimals(),
        }
    }

    // -----
    // Views
    // -----
    public fun name<T>(self: &TokenMetadata<T>): String {
        self.name
    }

    public fun symbol<T>(self: &TokenMetadata<T>): ascii::String {
        self.symbol
    }

    public fun decimals<T>(self: &TokenMetadata<T>): u8 {
        self.decimals
    }

    // === Tests ===
    #[test_only]
    use interchain_token_service::coin::COIN;

    #[test]
    fun test_from() {
        let ctx = &mut tx_context::dummy();
        let metadata = interchain_token_service::coin::create_metadata(b"Symbol", 8, ctx);
        let name = metadata.get_name();
        let symbol = metadata.get_symbol();
        let decimals = metadata.get_decimals();

        // from_info
        let from_info = from_info(name, symbol, decimals);

        // from_metadata
        let from_metadata = from_metadata(&metadata);

        // from coin_info
        let coin_info: CoinInfo<COIN> = coin_info::from_info(name, symbol, decimals);
        let from_coin_info = from_coin_info(&coin_info);

        assert!(from_metadata.name() == name);
        assert!(from_metadata.symbol() == symbol);
        assert!(from_metadata.decimals() == decimals);
        assert!(&from_info == &from_metadata);

        sui::test_utils::destroy(metadata);
        sui::test_utils::destroy(coin_info);
        sui::test_utils::destroy(from_info);
        sui::test_utils::destroy(from_metadata);
        sui::test_utils::destroy(from_coin_info);
    }
}
