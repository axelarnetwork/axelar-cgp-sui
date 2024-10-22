module example::b;

use sui::coin;

// ------------
// Capabilities
// ------------
public struct B has drop {}

// -----
// Setup
// -----
fun init(witness: B, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        9,
        b"ITS",
        b"ITS Example Coin",
        b"",
        option::none(),
        ctx,
    );
    transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
    transfer::public_transfer(coin_metadata, tx_context::sender(ctx));
}
