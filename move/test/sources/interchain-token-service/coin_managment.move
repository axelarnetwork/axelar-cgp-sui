

module interchain_token_service::coin_management {
    use std::option::{Self, Option};

    use sui::coin::{Self, TreasuryCap, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::tx_context::TxContext;

    friend interchain_token_service::service;

    const EDistributorNeedsTreasuryCap: u64 = 0;

    struct CoinManagement<phantom T> has store {
        has_capability: bool,
        treasury_cap: Option<TreasuryCap<T>>,
        balance: Option<Balance<T>>,
        distributor: Option<address>,
    }

    public fun mint_burn<T>(treasury_cap: TreasuryCap<T>) : CoinManagement<T> {
        CoinManagement<T> {
            has_capability: true,
            treasury_cap: option::some<TreasuryCap<T>>(treasury_cap),
            balance: option::none<Balance<T>>(),
            distributor: option::none<address>(),
        }
    }

    public fun lock_unlock<T>(): CoinManagement<T> {
        CoinManagement<T> {
            has_capability: true,
            treasury_cap: option::none<TreasuryCap<T>>(),
            balance: option::some<Balance<T>>(balance::zero<T>()),
            distributor: option::none<address>(),
        }
    }

    public fun lock_unlock_funded<T>(coin: Coin<T>): CoinManagement<T> {
        let balance = coin::into_balance(coin);
        CoinManagement<T> {
            has_capability: true,
            treasury_cap: option::none<TreasuryCap<T>>(),
            balance: option::some<Balance<T>>(balance),
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
            let balance = option::borrow_mut(&mut self.balance);
            coin::put(balance, to_take);
        }
    }

    public (friend) fun give_coin_to<T>(self: &mut CoinManagement<T>, to: address, amount: u64, ctx: &mut TxContext) {
        let coin = give_coin<T>(self, amount, ctx);
        transfer::public_transfer(coin, to);
    }

    public (friend) fun give_coin<T>(self: &mut CoinManagement<T>, amount: u64, ctx: &mut TxContext) : Coin<T> {
        if(self.has_capability) {
            let cap = option::borrow_mut(&mut self.treasury_cap);
            coin::mint(cap, amount, ctx)
        } else {
            let balance = option::borrow_mut(&mut self.balance);
            coin::take<T>(balance, amount, ctx)
        }
    }

    public fun is_distributor<T>(self: &CoinManagement<T>, distributor: address): bool {
        option::contains(&self.distributor, &distributor)
    }
}