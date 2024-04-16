module interchain_token::$module_name {
    use sui::coin::{Self};
    use sui::url::{Url};

    public struct $witness has drop {}

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