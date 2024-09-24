module example::coin;

use sui::coin::{Self, TreasuryCap, CoinMetadata};
use sui::transfer;
use sui::url::Url;

/// The type of coin. Used as a phantom parameter in `Coin<COIN>`
public struct COIN has drop {}

/// Create and store the currency
fun init(witness: COIN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<COIN>(
            witness,
            9,
            b"Symbol",
            b"Name",
            b"",
            option::none<Url>(),
            ctx
    );

    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury_cap, tx_context::sender(ctx))
}


