module example::token;

use sui::coin::{Self, TreasuryCap};

// ------------
// Capabilities
// ------------
public struct TOKEN has drop {}

// -----
// Setup
// -----
fun init(witness: TOKEN, ctx: &mut TxContext) {
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

public fun mint(
    treasury_cap: &mut TreasuryCap<TOKEN>,
    amount: u64,
    to: address,
    ctx: &mut TxContext,
) {
    treasury_cap.mint_and_transfer(amount, to, ctx);
}
