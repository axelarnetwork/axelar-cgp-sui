module example::token_c {
    use sui::coin;

    // ------------
    // Capabilities
    // ------------
    public struct TOKEN_C has drop {}

    // -----
    // Setup
    // -----
    fun init(witness: TOKEN_C, ctx: &mut TxContext) {
        let (treasury_cap, coin_metadata) = coin::create_currency(
            witness,
            9,
            b"TOKEN3",
            b"Token 3",
            b"",
            option::none(),
            ctx,
        );
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_transfer(coin_metadata, tx_context::sender(ctx));
    }
}
