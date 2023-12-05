

module interchain_token_service::coin_management {
    use std::option::{Self, Option};

    use sui::coin::{Self, TreasuryCap, Coin};
    use sui::transfer;
    use sui::tx_context::TxContext;

    friend interchain_token_service::service;

    const EDistributorNeedsTreasuryCap: u64 = 0;

    struct CoinManagement<phantom T> has store{
        has_capability: bool,
        treasury_cap: Option<TreasuryCap<T>>,
        coin: Option<Coin<T>>,
        distributor: Option<address>,
    }

    public fun mint_burn<T>(treasury_cap: TreasuryCap<T>) : CoinManagement<T> {
        CoinManagement<T> {
            has_capability: true,
            treasury_cap: option::some<TreasuryCap<T>>(treasury_cap),
            coin: option::none<Coin<T>>(),
            distributor: option::none<address>(),
        }
    }

    public fun lock_unlock<T>(ctx: &mut TxContext): CoinManagement<T> {
        let coin = coin::zero<T>(ctx);
        CoinManagement<T> {
            has_capability: true,
            treasury_cap: option::none<TreasuryCap<T>>(),
            coin: option::some<Coin<T>>(coin),
            distributor: option::none<address>(),
        }
    }

    public fun lock_unlock_funded<T>(coin: Coin<T>): CoinManagement<T> {
        CoinManagement<T> {
            has_capability: true,
            treasury_cap: option::none<TreasuryCap<T>>(),
            coin: option::some<Coin<T>>(coin),
            distributor: option::none<address>(),
        }
    }

    public fun add_distributor<T>(self: &mut CoinManagement<T>, distributor: address) {
        assert!(self.has_capability, EDistributorNeedsTreasuryCap);
        option::fill(&mut self.distributor, distributor);
    }

    public (friend) fun take_coin<T>(self: &mut CoinManagement<T>, to_take: Coin<T>) {
        if(self.has_capability) {
            let cap = option::borrow_mut(&mut self.treasury_cap);
            coin::burn(cap, to_take);
        } else {
            let coin = option::borrow_mut(&mut self.coin);
            coin::join(coin, to_take);
        }
    }

    public (friend) fun give_coin_to<T>(self: &mut CoinManagement<T>, to: address, amount: u64, ctx: &mut TxContext) {
        if(self.has_capability) {
            let cap = option::borrow_mut(&mut self.treasury_cap);
            coin::mint_and_transfer(cap, amount, to, ctx);
        } else {
            let coin = option::borrow_mut(&mut self.coin);
            let to_give = coin::split<T>(coin, amount, ctx);
            transfer::public_transfer(to_give, to);
        }
    }

    public (friend) fun give_coin<T>(self: &mut CoinManagement<T>, amount: u64, ctx: &mut TxContext) : Coin<T> {
        if(self.has_capability) {
            let cap = option::borrow_mut(&mut self.treasury_cap);
            coin::mint(cap, amount, ctx)
        } else {
            let coin = option::borrow_mut(&mut self.coin);
            coin::split<T>(coin, amount, ctx)
        }
    }

    public fun is_distributor<T>(self: &CoinManagement<T>, distributor: address): bool {
        option::contains(&self.distributor, &distributor)
    }
}