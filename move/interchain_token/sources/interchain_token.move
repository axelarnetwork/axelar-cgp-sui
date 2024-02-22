module interchain_token::tt {
    use sui::tx_context::TxContext;
    use std::option;

    use sui::coin;
    use sui::transfer;

    public struct TT has drop {}

    fun init(witness: TT, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<TT>(
            witness,
            6,
            b"TT",
            b"Test Token",
            b"",
            option::none(),
            ctx
        );
        transfer::public_transfer(treasury, ctx.sender());
        transfer::public_transfer(metadata, ctx.sender());
    }
}
