module interchain_token::q;

use sui::coin;
use sui::url::Url;

public struct Q has drop {}

fun init(witness: Q, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency<Q>(
        witness,
        9,
        b"Q",
        b"Quote",
        b"",
        option::none<Url>(),
        ctx,
    );
    transfer::public_transfer(treasury, tx_context::sender(ctx));
    transfer::public_transfer(metadata, tx_context::sender(ctx));
}
