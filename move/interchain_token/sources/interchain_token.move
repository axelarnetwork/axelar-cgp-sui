module interchain_token::b {
    use sui::coin::{Self};
    use sui::url::{Url};

    public struct B has drop {}

    fun init(witness: B, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<B>(
            witness,
            9,
            b"B",
            b"Base",
            b"",
            option::none<Url>(),
            ctx
        );
        transfer::public_transfer(treasury, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
    }
}
