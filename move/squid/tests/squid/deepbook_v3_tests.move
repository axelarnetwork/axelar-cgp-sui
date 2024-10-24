#[test_only]
module squid::deepbook_v3_tests;

use deepbook::pool::Pool;
use deepbook::pool_tests;
use squid::deepbook_v3;
use squid::swap_info;
use squid::swap_type;
use std::type_name;
use sui::clock::Clock;
use sui::coin::mint_for_testing;
use sui::object::id_to_address;
use sui::sui::SUI;
use sui::test_scenario::{begin, end};
use sui::test_utils::{destroy, assert_eq};
use token::deep::DEEP;

public struct USDC has store {}

const OWNER: address = @0x1;

#[test]
fun test_serialize() {
    let mut test = begin(OWNER);
    let pool_id = pool_tests::setup_everything<SUI, USDC, SUI, DEEP>(&mut test);

    test.next_tx(OWNER);
    let swap_data = deepbook_v3::new_swap_data(
        swap_type::deepbook_v3(),
        id_to_address(&pool_id),
        true,
        100,
        type_name::get<SUI>().into_string(),
        type_name::get<USDC>().into_string(),
        1,
        true,
    );
    let swap_data_vec = std::bcs::to_bytes(&swap_data);
    let data = std::bcs::to_bytes(&vector[swap_data_vec]);
    let mut swap_info = swap_info::new(data, test.ctx());
    let (data2, _) = swap_info.data_estimating();
    let swap_data2 = deepbook_v3::peel_swap_data(data2);
    assert_eq(swap_data, swap_data2);

    let clock = test.take_shared<Clock>();
    let pool = test.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
    destroy(pool);
    destroy(clock);
    destroy(swap_info);

    end(test);
}

#[test]
fun test_estimate() {
    let mut test = begin(OWNER);
    let pool_id = pool_tests::setup_everything<SUI, USDC, DEEP, USDC>(
        &mut test,
    );

    test.next_tx(OWNER);
    let swap_data = deepbook_v3::new_swap_data(
        swap_type::deepbook_v3(),
        id_to_address(&pool_id),
        true,
        100,
        type_name::get<SUI>().into_string(),
        type_name::get<USDC>().into_string(),
        1,
        true,
    );
    let swap_data_vec = std::bcs::to_bytes(&swap_data);
    let data = std::bcs::to_bytes(&vector[swap_data_vec]);
    let mut swap_info = swap_info::new(data, test.ctx());
    // Store 100 SUI as estimate
    swap_info.coin_bag().store_estimate<SUI>(100_000_000_000);

    // The pool comes with a bid at $1 with quantity 1000. Taker fee of 10bps.
    // When estimating, we should take 10bps worth of SUI out, then swap the
    // rest for USDC.
    let clock = test.take_shared<Clock>();
    let mut pool = test.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
    deepbook_v3::estimate(&mut swap_info, &pool, &clock);

    // This will call DeepBook's pool with base_in of 99.9 SUI. Since there is a
    // bid at $1
    // It will output 99.9 worth of USDC can be obtained.
    let estimate = swap_info.coin_bag().estimate<USDC>();
    assert!(estimate == 99_900_000_000);

    // Create Squid and load it with DEEP. Load swap_info with 100 SUI.
    let mut squid = squid::squid::new_for_testing(test.ctx());
    let sui_coin = mint_for_testing<SUI>(100_000_000_000, test.ctx());
    let deep_coin = mint_for_testing<DEEP>(100_000_000_000, test.ctx());
    swap_info.coin_bag().store_balance(sui_coin.into_balance());
    squid
        .value_mut!(b"")
        .coin_bag_mut()
        .store_balance(deep_coin.into_balance());

    // Swap 100 SUI for 99.9 USDC
    deepbook_v3::swap(
        &mut swap_info,
        &mut pool,
        &mut squid,
        &clock,
        test.ctx(),
    );

    // The pool is set up with a DEEP/USDC conversion rate at 1 DEEP = 100 USDC.
    // With that conversion rate and 10bps taker fee, the DEEP required
    // to trade 99.9 SUI to 99.9 USDC is 99.9 * 0.001 / 100 = 0.000999 DEEP = 999_000.

    // swap_info should have a balance of 99.9 USDC
    // squid should have a balance of 100 DEEP
    let quote_balance = swap_info.coin_bag().balance<USDC>().destroy_some();
    assert!(quote_balance.value() == 99_900_000_000);
    let deep_balance = squid
        .value_mut!(b"")
        .coin_bag_mut()
        .balance<DEEP>()
        .destroy_some();
    assert!(deep_balance.value() == 100_000_000_000 - 999_000);

    destroy(pool);
    destroy(clock);
    destroy(swap_info);
    destroy(squid);
    destroy(quote_balance);
    destroy(deep_balance);

    end(test);
}
