module interchain_token::tt {
    use sui::tx_context::{Self, TxContext};
    use std::option;

    use sui::coin::{Self};
    use sui::url::{Url};
    use sui::transfer;

    struct TT has drop {}

    fun init(witness: TT, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<TT>(
            witness,
            6,
            b"",
            b"",
            b"",
            option::none<Url>(),
            ctx
        );
        transfer::public_transfer(treasury, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
    }
}