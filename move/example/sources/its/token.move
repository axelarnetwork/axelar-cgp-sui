module example::token;

use axelar_gateway::channel::{Self, Channel};
use sui::coin::{Self, CoinMetadata, TreasuryCap};

// -------
// Structs
// -------
public struct Singleton has key {
    id: UID,
    channel: Channel,
    coin_metadata: CoinMetadata<TOKEN>,
    treasury_cap: TreasuryCap<TOKEN>,
}


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
    let singletonId = object::new(ctx);
    let channel = channel::new(ctx);
    transfer::share_object(Singleton {
        id: singletonId,
        channel,
        coin_metadata,
        treasury_cap,
    });
}

// -----
// Getters
// -----
public fun get_channel(self: &Singleton): &Channel {
    &self.channel
}

public fun get_coin_metadata(self: &Singleton): &CoinMetadata<TOKEN> {
    &self.coin_metadata
}


/// -----
/// Public Functions
/// -----
/// Call this to obtain some coins for testing.
public fun mint(self: &mut Singleton, amount: u64, to: address, ctx: &mut TxContext) {
	self.treasury_cap.mint_and_transfer(amount, to, ctx);
}
