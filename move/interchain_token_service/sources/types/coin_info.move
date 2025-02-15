/// Defines the `CoinInfo` type which allows to store information about a coin:
/// either derived from `CoinMetadata` or manually provided.
module interchain_token_service::coin_info {
    use std::{ascii, string::String};
    use sui::coin::CoinMetadata;

    public struct CoinInfo<phantom T> has store {
        name: String,
        symbol: ascii::String,
        decimals: u8,
        metadata: Option<CoinMetadata<T>>,
    }

    /// Create a new coin info from the given name, symbol and decimals.
    public fun from_info<T>(name: String, symbol: ascii::String, decimals: u8): CoinInfo<T> {
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
            name: metadata.get_name(),
            symbol: metadata.get_symbol(),
            decimals: metadata.get_decimals(),
            metadata: option::some(metadata),
        }
    }

    // -----
    // Views
    // -----
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

    // === Tests ===
    #[error]
    #[test_only]
    const EMetadataExists: vector<u8> = b"metadata was expected to be empty";

    #[test_only]
    public fun drop<T>(coin_info: CoinInfo<T>) {
        let CoinInfo {
            name: _,
            symbol: _,
            decimals: _,
            metadata,
        } = coin_info;
        if (metadata.is_some()) {
            abort EMetadataExists
        } else {
            metadata.destroy_none()
        }
    }

    #[test]
    fun test_from_metadata() {
        let ctx = &mut tx_context::dummy();
        let metadata = interchain_token_service::coin::create_metadata(b"Symbol", 8, ctx);
        let metadata_bytes = sui::bcs::to_bytes(&metadata);

        let name = metadata.get_name();
        let symbol = metadata.get_symbol();
        let decimals = metadata.get_decimals();

        let coin_info = from_metadata(metadata);

        assert!(coin_info.name() == name);
        assert!(coin_info.symbol() == symbol);
        assert!(coin_info.decimals() == decimals);
        assert!(sui::bcs::to_bytes(coin_info.metadata().borrow()) == metadata_bytes);

        sui::test_utils::destroy(coin_info);
    }
}
