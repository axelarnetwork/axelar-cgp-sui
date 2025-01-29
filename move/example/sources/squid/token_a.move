module example::token_a {
    use sui::coin;

    // ------------
    // Capabilities
    // ------------
    public struct TOKEN_A has drop {}

    // -----
    // Setup
    // -----
    fun init(witness: TOKEN_A, ctx: &mut TxContext) {
        let (treasury_cap, coin_metadata) = coin::create_currency(
            witness,
            9,
            b"TOKEN1",
            b"Token 1",
            b"",
            option::none(),
            ctx,
        );
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_transfer(coin_metadata, tx_context::sender(ctx));
    }
}
