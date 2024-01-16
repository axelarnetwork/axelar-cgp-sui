module interchain_token::$module_name {
    use sui::tx_context::{Self, TxContext};
    use std::option;

    use sui::coin::{Self};
    use sui::url::{Url};
    use sui::transfer;

    struct $witness has drop {}

    fun init(witness: $witness, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<$witness>(
            witness,
            $decimals,
            b"$symbol",
            b"$name",
            b"",
            option::none<Url>(),
            ctx
        );
        transfer::public_transfer(treasury, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
    }
}