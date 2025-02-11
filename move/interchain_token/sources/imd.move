module interchain_token::imd{
    use sui::{coin, url::Url};

    public struct IMD has drop {}

    fun init(witness: IMD, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<IMD>(
            witness,
            6,
            b"IMD",
            b"Interchain Moo Deng",
            b"",
            option::none<Url>(),
            ctx,
        );
        transfer::public_transfer(treasury, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
    }
}
