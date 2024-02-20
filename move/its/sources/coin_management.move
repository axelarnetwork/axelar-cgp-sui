

module its::coin_management {
    use std::option::{Self, Option};

    use sui::coin::{Self, TreasuryCap, Coin};
    use sui::balance::{Self, Balance};
    use sui::tx_context::TxContext;

    friend its::service;

    /// Trying to add a distributor to a `CoinManagement` that does not
    /// have a `TreasuryCap`.
    const EDistributorNeedsTreasuryCap: u64 = 0;

    /// Struct that stores information about the ITS Coin.
    public struct CoinManagement<phantom T> has store {
        treasury_cap: Option<TreasuryCap<T>>,
        balance: Option<Balance<T>>,
        distributor: Option<address>,
    }

    /// Create a new `CoinManagement` with a `TreasuryCap`.
    /// This type of `CoinManagement` allows minting and burning of coins.
    public fun new_with_cap<T>(treasury_cap: TreasuryCap<T>): CoinManagement<T> {
        CoinManagement<T> {
            treasury_cap: option::some(treasury_cap),
            balance: option::none(),
            distributor: option::none(),
        }
    }

    /// Create a new `CoinManagement` with a `Balance`.
    /// The stored `Balance` can be used to take and put coins.
    public fun new_locked<T>(): CoinManagement<T> {
        CoinManagement<T> {
            treasury_cap: option::none(),
            balance: option::some(balance::zero()),
            distributor: option::none(),
        }
    }

    /// Adds the distributor address to the `CoinManagement`.
    /// Only works for a `CoinManagement` with a `TreasuryCap`.
    public fun add_distributor<T>(self: &mut CoinManagement<T>, distributor: address) {
        assert!(has_capability(self), EDistributorNeedsTreasuryCap);
        self.distributor.fill(distributor);
    }

    // === Protected Methods ===

    /// Takes the given amount of Coins from user.
    public(friend) fun take_coin<T>(self: &mut CoinManagement<T>, to_take: Coin<T>) {
        if (has_capability(self)) {
            self.treasury_cap
                .borrow_mut()
                .burn(to_take);
        } else {
            self.balance
                .borrow_mut()
                .join(to_take.into_balance());
        }
    }

    /// Withdraws or mints the given amount of coins.
    public(friend) fun give_coin<T>(
        self: &mut CoinManagement<T>, amount: u64, ctx: &mut TxContext
    ): Coin<T> {
        if (has_capability(self)) {
            self.treasury_cap
                .borrow_mut()
                .mint(amount, ctx)
        } else {
            coin::take(self.balance.borrow_mut(), amount, ctx)
        }
    }

    // === Views ===

    /// Checks if the given address is a `distributor`.
    public fun is_distributor<T>(self: &CoinManagement<T>, distributor: address): bool {
        &distributor == self.distributor.borrow()
    }

    /// Returns true if the coin management has a `TreasuryCap`.
    public fun has_capability<T>(self: &CoinManagement<T>): bool {
        self.treasury_cap.is_some()
    }
}
