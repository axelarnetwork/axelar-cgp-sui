module squid::deepbook_v3;

use std::ascii::{Self, String};
use std::type_name;

use sui::bcs::{Self, BCS};
use sui::clock::Clock;

use deepbook::pool::Pool;

use relayer_discovery::transaction::{Self, MoveCall};

use squid::squid::Squid;
use squid::swap_info::SwapInfo;
use squid::swap_type::{Self, SwapType};

use token::deep::DEEP;


const EWrongSwapType: u64 = 0;
const EWrongPool: u64 = 1;
const EWrongCoinType: u64 = 2;

const FLOAT_SCALING: u128 = 1_000_000_000;

public struct DeepbookV3SwapData has drop {
    swap_type: SwapType,
    pool_id: address,
    has_base: bool,
    min_output: u64,
    base_type: String,
    quote_type: String,
    lot_size: u64,
    should_sweep: bool,
}

/// Estimate the output of a swap. If the output is less than the minimum
/// output, the swap is skipped.
/// If the swap is not skipped, the estimate is stored in the coin bag.
public fun estimate<B, Q>(
    self: &mut SwapInfo,
    pool: &Pool<B, Q>,
    clock: &Clock,
) {
    let (data, fallback) = self.data_estimating();
    if (fallback) return;
    let swap_data = peel_swap_data(data);

    assert!(swap_data.swap_type == swap_type::deepbook_v3(), EWrongSwapType);
    assert!(swap_data.pool_id == object::id_address(pool), EWrongPool);
    assert!(
        &swap_data.base_type == &type_name::get<B>().into_string(),
        EWrongCoinType,
    );
    assert!(
        &swap_data.quote_type == &type_name::get<Q>().into_string(),
        EWrongCoinType,
    );

    let (taker_fee, _, _) = pool.pool_trade_params();

    if (swap_data.has_base) {
        let base_quantity = self.coin_bag().estimate<B>();
        let base_fee = mul_scaled(base_quantity, taker_fee);
        let base_in = base_quantity - base_fee;

        let (base_out, quote_out, _deep_required) = pool.get_quote_quantity_out(
            base_in,
            clock,
        );
        if (swap_data.min_output > quote_out) {
            self.skip_swap();
            return
        };
        if (!swap_data.should_sweep) {
            self.coin_bag().store_estimate<B>(base_out)
        };
        self.coin_bag().store_estimate<Q>(quote_out);
    } else {
        let quote_quantity = self.coin_bag().estimate<Q>();
        let quote_fee = mul_scaled(quote_quantity, taker_fee);
        let quote_in = quote_quantity - quote_fee;

        let (base_out, quote_out, _deep_required) = pool.get_base_quantity_out(
            quote_in,
            clock,
        );
        if (swap_data.min_output > base_out) {
            self.skip_swap();
            return
        };
        if (!swap_data.should_sweep) {
            self.coin_bag().store_estimate<Q>(quote_out)
        };
        self.coin_bag().store_estimate<B>(base_out);
    }
}

/// Perform a swap. First, check how much DEEP is required to perform the swap.
/// Then, get that amount of DEEP from squid. Get the taker_fee for this swap
/// and
/// split that amount from the input token. Store the fee in Squid. Use the
/// remaining
/// input token to perform the swap. Store the output tokens in the coin bag.
/// Store the remaining DEEP back in squid.
public fun swap<B, Q>(
    self: &mut SwapInfo,
    pool: &mut Pool<B, Q>,
    squid: &mut Squid,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (data, fallback) = self.data_swapping();
    if (fallback) return;
    let swap_data = peel_swap_data(data);

    assert!(swap_data.swap_type == swap_type::deepbook_v3(), EWrongSwapType);
    assert!(swap_data.pool_id == object::id_address(pool), EWrongPool);
    assert!(
        &swap_data.base_type == &type_name::get<B>().into_string(),
        EWrongCoinType,
    );
    assert!(
        &swap_data.quote_type == &type_name::get<Q>().into_string(),
        EWrongCoinType,
    );

    let (taker_fee, _, _) = pool.pool_trade_params();

    let squid_coin_bag = squid.value_mut!(b"deepbook_v3_swap").coin_bag_mut();

    if (swap_data.has_base) {
        // Get base coin, split away taker fees and store it in Squid.
        let mut base_in = self
            .coin_bag()
            .balance<B>()
            .destroy_some()
            .into_coin(ctx);
        let base_fee_amount = mul_scaled(base_in.value(), taker_fee);
        let base_fee = base_in.split(base_fee_amount, ctx);
        squid_coin_bag.store_balance(base_fee.into_balance());

        // Calculate the DEEP quantity required and get it from Squid.
        let (_, _, deep_required) = pool.get_quote_quantity_out(
            base_in.value(),
            clock,
        );
        let deep_in = squid_coin_bag
            .exact_balance<DEEP>(deep_required)
            .into_coin(ctx);

        let (base_out, quote_out, deep_out) = pool.swap_exact_base_for_quote<
            B,
            Q,
        >(
            base_in,
            deep_in,
            swap_data.min_output,
            clock,
            ctx,
        );

        self.coin_bag().store_balance(quote_out.into_balance());
        squid_coin_bag.store_balance(deep_out.into_balance());
        if (swap_data.should_sweep) {
            squid_coin_bag.store_balance(base_out.into_balance());
        } else {
            self.coin_bag().store_balance(base_out.into_balance());
        };
    } else {
        // Get quote coin, split away taker fees and store it in Squid.
        let mut quote_in = self
            .coin_bag()
            .balance<Q>()
            .destroy_some()
            .into_coin(ctx);
        let quote_fee_amount = mul_scaled(quote_in.value(), taker_fee);
        let quote_fee = quote_in.split(quote_fee_amount, ctx);
        squid_coin_bag.store_balance(quote_fee.into_balance());

        // Calculate the DEEP quantity required and get it from Squid.
        let (_, _, deep_required) = pool.get_base_quantity_out(
            quote_in.value(),
            clock,
        );
        let deep_in = squid_coin_bag
            .exact_balance<DEEP>(deep_required)
            .into_coin(ctx);

        let (quote_out, base_out, deep_out) = pool.swap_exact_quote_for_base<
            B,
            Q,
        >(
            quote_in,
            deep_in,
            swap_data.min_output,
            clock,
            ctx,
        );

        self.coin_bag().store_balance(base_out.into_balance());
        squid_coin_bag.store_balance(deep_out.into_balance());
        if (swap_data.should_sweep) {
            squid_coin_bag.store_balance(quote_out.into_balance());
        } else {
            self.coin_bag().store_balance(quote_out.into_balance());
        };
    }
}

public(package) fun estimate_move_call(
    package_id: address,
    mut bcs: BCS,
    swap_info_arg: vector<u8>,
): MoveCall {
    let mut pool_arg = vector[0];
    pool_arg.append(bcs.peel_address().to_bytes());

    let _has_base = bcs.peel_bool();
    let _min_output = bcs.peel_u64();

    let type_base = ascii::string(bcs.peel_vec_u8());
    let type_quote = ascii::string(bcs.peel_vec_u8());

    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"deepbook_v3"),
            ascii::string(b"estimate"),
        ),
        vector[swap_info_arg, pool_arg, vector[0, 6]],
        vector[type_base, type_quote],
    )
}

public(package) fun swap_move_call(
    package_id: address,
    mut bcs: BCS,
    swap_info_arg: vector<u8>,
    squid_arg: vector<u8>,
): MoveCall {
    let mut pool_arg = vector[0];
    pool_arg.append(bcs.peel_address().to_bytes());

    let _has_base = bcs.peel_bool();
    let _min_output = bcs.peel_u64();

    let type_base = ascii::string(bcs.peel_vec_u8());
    let type_quote = ascii::string(bcs.peel_vec_u8());

    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"deepbook_v3"),
            ascii::string(b"swap"),
        ),
        vector[swap_info_arg, pool_arg, squid_arg, vector[0, 6]],
        vector[type_base, type_quote],
    )
}

public(package) fun peel_swap_data(data: vector<u8>): DeepbookV3SwapData {
    let mut bcs = bcs::new(data);
    DeepbookV3SwapData {
        swap_type: swap_type::peel(&mut bcs),
        pool_id: bcs.peel_address(),
        has_base: bcs.peel_bool(),
        min_output: bcs.peel_u64(),
        base_type: ascii::string(bcs.peel_vec_u8()),
        quote_type: ascii::string(bcs.peel_vec_u8()),
        lot_size: bcs.peel_u64(),
        should_sweep: bcs.peel_bool(),
    }
}

/// Multiply two u64 numbers and divide by FLOAT_SCALING. Rounded down.
/// Used for multiplying the balance by DeepBook's taker fee.
fun mul_scaled(x: u64, y: u64): u64 {
    let x = x as u128;
    let y = y as u128;

    ((x * y / FLOAT_SCALING) as u64)
}

#[test_only]
public(package) fun new_swap_data(
    swap_type: SwapType,
    pool_id: address,
    has_base: bool,
    min_output: u64,
    base_type: String,
    quote_type: String,
    lot_size: u64,
    should_sweep: bool,
): DeepbookV3SwapData {
    DeepbookV3SwapData {
        swap_type,
        pool_id,
        has_base,
        min_output,
        base_type,
        quote_type,
        lot_size,
        should_sweep,
    }
}
