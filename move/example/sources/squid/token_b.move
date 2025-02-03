module example::token_b {
    use sui::coin;

    // ------------
    // Capabilities
    // ------------
    public struct TOKEN_B has drop {}

    // -----
    // Setup
    // -----
    fun init(witness: TOKEN_B, ctx: &mut TxContext) {
        let (treasury_cap, coin_metadata) = coin::create_currency(
            witness,
            9,
            b"TOKEN2",
            b"Token 2",
            b"",
            option::none(),
            ctx,
        );
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_transfer(coin_metadata, tx_context::sender(ctx));
    }
}
