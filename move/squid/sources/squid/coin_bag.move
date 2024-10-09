module squid::coin_bag;

use std::type_name;
use sui::address;
use sui::bag::{Self, Bag};
use sui::balance::Balance;
use sui::hash::keccak256;

const EKeyNotExist: u64 = 0;
const ENotEnoughBalance: u64 = 1;

public struct CoinBag has store {
    bag: Bag,
}

public(package) fun new(ctx: &mut TxContext): CoinBag {
    CoinBag {
        bag: bag::new(ctx),
    }
}

public(package) fun store_balance<T>(self: &mut CoinBag, balance: Balance<T>) {
    let key = balance_key<T>();

    if (self.bag.contains(key)) {
        self
            .bag
            .borrow_mut<address, Balance<T>>(key)
            .join(
                balance,
            );
    } else {
        self
            .bag
            .add(
                key,
                balance,
            )
    }
}

public(package) fun balance<T>(self: &mut CoinBag): Option<Balance<T>> {
    let key = balance_key<T>();

    if (self.bag.contains(key)) {
        option::some(self.bag.remove<address, Balance<T>>(key))
    } else {
        option::none<Balance<T>>()
    }
}

public(package) fun exact_balance<T>(
    self: &mut CoinBag,
    amount: u64,
): Balance<T> {
    let key = balance_key<T>();

    assert!(self.bag.contains(key), EKeyNotExist);
    let balance = self.bag.borrow_mut<address, Balance<T>>(key);
    assert!(balance.value() >= amount, ENotEnoughBalance);

    balance.split(amount)
}

public(package) fun balance_amount<T>(self: &CoinBag): u64 {
    let key = balance_key<T>();

    if (self.bag.contains(key)) {
        self.bag.borrow<address, Balance<T>>(key).value()
    } else {
        0
    }
}

public(package) fun store_estimate<T>(self: &mut CoinBag, estimate: u64) {
    let key = estimate_key<T>();

    if (self.bag.contains(key)) {
        let previous = self.bag.borrow_mut<address, u64>(key);
        *previous = *previous + estimate;
    } else {
        self
            .bag
            .add(
                key,
                estimate,
            )
    }
}

public(package) fun estimate<T>(self: &mut CoinBag): u64 {
    let key = estimate_key<T>();

    if (self.bag.contains(key)) {
        self.bag.remove<address, u64>(key)
    } else {
        0
    }
}

public(package) fun estimate_amount<T>(self: &CoinBag): u64 {
    let key = estimate_key<T>();

    if (self.bag.contains(key)) {
        *self.bag.borrow<address, u64>(key)
    } else {
        0
    }
}

public(package) fun destroy(self: CoinBag) {
    let CoinBag { bag } = self;
    bag.destroy_empty();
}

fun balance_key<T>(): address {
    let mut data = vector[0];
    data.append(type_name::get<T>().into_string().into_bytes());
    address::from_bytes(keccak256(&data))
}

fun estimate_key<T>(): address {
    let mut data = vector[1];
    data.append(type_name::get<T>().into_string().into_bytes());
    address::from_bytes(keccak256(&data))
}

#[test_only]
use its::coin::COIN;

#[test]
fun test_balance() {
    let ctx = &mut tx_context::dummy();
    let mut coin_bag = new(ctx);

    assert!(coin_bag.balance_amount<COIN>() == 0);

    coin_bag.store_balance(sui::balance::create_for_testing<COIN>(1));
    assert!(coin_bag.balance_amount<COIN>() == 1);

    coin_bag.store_balance(sui::balance::create_for_testing<COIN>(2));
    let mut balance = coin_bag.balance<COIN>();
    assert!(balance.borrow().value() == 3);
    sui::test_utils::destroy(balance);

    balance = coin_bag.balance<COIN>();
    assert!(balance.is_none());
    balance.destroy_none();

    coin_bag.destroy();
}

#[test]
fun test_estimate() {
    let ctx = &mut tx_context::dummy();
    let mut coin_bag = new(ctx);

    assert!(coin_bag.estimate_amount<COIN>() == 0);

    coin_bag.store_estimate<COIN>(1);
    assert!(coin_bag.estimate_amount<COIN>() == 1);

    coin_bag.store_estimate<COIN>(2);
    let mut estimate = coin_bag.estimate<COIN>();
    assert!(estimate == 3);

    estimate = coin_bag.estimate<COIN>();
    assert!(estimate == 0);

    coin_bag.destroy();
}
