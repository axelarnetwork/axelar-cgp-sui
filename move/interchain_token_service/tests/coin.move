#[test_only]
module interchain_token_service::coin {
    use sui::{coin::{Self, CoinMetadata, TreasuryCap}, url::Url};

    public struct COIN has drop {}

    // -----
    // Coin creation functions.
    // -----

    public fun create_treasury_and_metadata(
        symbol: vector<u8>,
        decimals: u8,
        ctx: &mut TxContext,
    ): (TreasuryCap<COIN>, CoinMetadata<COIN>) {
        coin::create_currency<COIN>(
            COIN {},
            decimals,
            symbol,
            b"Name",
            b"",
            option::none<Url>(),
            ctx,
        )
    }

    public fun create_treasury_and_metadata_custom(
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        url: Option<Url>,
        ctx: &mut TxContext,
    ): (TreasuryCap<COIN>, CoinMetadata<COIN>) {
        coin::create_currency<COIN>(
            COIN {},
            decimals,
            symbol,
            name,
            b"",
            url,
            ctx,
        )
    }

    public fun create_treasury(symbol: vector<u8>, decimals: u8, ctx: &mut TxContext): TreasuryCap<COIN> {
        let (treasury, metadata) = create_treasury_and_metadata(
            symbol,
            decimals,
            ctx,
        );

        sui::test_utils::destroy(metadata);

        treasury
    }

    public fun create_metadata(symbol: vector<u8>, decimals: u8, ctx: &mut TxContext): CoinMetadata<COIN> {
        let (treasury, metadata) = create_treasury_and_metadata(
            symbol,
            decimals,
            ctx,
        );

        sui::test_utils::destroy(treasury);

        metadata
    }
}
