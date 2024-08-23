module squid::squid;

use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
use its::its::ITS;
use its::service;
use squid::coin_bag::{Self, CoinBag};
use squid::swap_info::{Self, SwapInfo};
use sui::clock::Clock;

public struct Squid has key, store {
    id: UID,
    channel: Channel,
    coin_bag: CoinBag,
}

fun init(ctx: &mut TxContext) {
    transfer::share_object(Squid {
        id: object::new(ctx),
        channel: channel::new(ctx),
        coin_bag: coin_bag::new(ctx),
    });
}

public(package) fun borrow_channel(self: &Squid): &Channel {
    &self.channel
}

public fun start_swap<T>(
    self: &mut Squid,
    its: &mut ITS,
    approved_message: ApprovedMessage,
    clock: &Clock,
    ctx: &mut TxContext,
): SwapInfo {
    let (_, _, data, coin) = service::receive_interchain_transfer_with_data<T>(
        its,
        approved_message,
        &self.channel,
        clock,
        ctx,
    );
    let mut swap_info = swap_info::new(data, ctx);
    swap_info.coin_bag().store_estimate<T>(coin.value());
    swap_info.coin_bag().store_balance(coin.into_balance());
    swap_info
}

public(package) fun coin_bag(self: &mut Squid): &mut CoinBag {
    &mut self.coin_bag
}
