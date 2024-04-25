module interchain_token::tt {
    use sui::coin::{Self};
    use sui::url::{Url};

    public struct TT has drop {}

    fun init(witness: TT, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<TT>(
            witness,
            6,
            b"TT",
            b"Test Token",
            b"",
            option::none<Url>(),
            ctx
        );
        transfer::public_transfer(treasury, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
    }
}