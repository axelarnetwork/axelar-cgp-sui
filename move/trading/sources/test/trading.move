module trading::trading {
    use deepbook::clob_v2::{Self as clob, Pool};
    use deepbook::custodian_v2::{Self as custodian};
    use deepbook::math as clob_math;

    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event;

    const FLOAT_SCALING_U128: u128 = 1_000_000_000;
    const FLOAT_SCALING: u64 = 1_000_000_000;

    public struct Event has copy, drop {
        amount_left: u64,
        output: u64,
    }

    public fun swap_base<T1, T2>(pool: &mut Pool<T1, T2>, coin: Coin<T1>, clock: &Clock, ctx: &mut TxContext): (Coin<T1>, Coin<T2>) {
        let account = clob::create_account(ctx);
        let (base_coin, quote_coin, _) = pool.swap_exact_base_for_quote(
            0,
            &account,
            coin::value(&coin),
            coin,
            coin::zero<T2>(ctx),
            clock,
            ctx,
        );
        custodian::delete_account_cap(account);
        (base_coin, quote_coin)
    }

    public fun swap_quote<T1, T2>(pool: &mut Pool<T1, T2>, coin: Coin<T2>, clock: &Clock, ctx: &mut TxContext): (Coin<T1>, Coin<T2>) {
        let account = clob::create_account(ctx);
        let (base_coin, quote_coin, _) = pool.swap_exact_quote_for_base(
            0,
            &account,
            coin::value(&coin),
            clock,
            coin,
            ctx,
        );
        custodian::delete_account_cap(account);
        (base_coin, quote_coin)
    }

    // multiply two floating numbers
    // also returns whether the result is rounded down
    fun unsafe_mul_round(x: u64, y: u64): (bool, u64) {
        let x = x as u128;
        let y = y as u128;
        let mut is_round_down = true;
        if ((x * y) % FLOAT_SCALING_U128 == 0) is_round_down = false;
        (is_round_down, (x * y / FLOAT_SCALING_U128) as u64)
    }


    // divide two floating numbers
    // also returns whether the result is rounded down
    fun unsafe_div_round(x: u64, y: u64): (bool, u64) {
        let x = x as u128;
        let y = y as u128;
        let mut is_round_down = true;
        if ((x * (FLOAT_SCALING as u128) % y) == 0) is_round_down = false;
        (is_round_down, (x * (FLOAT_SCALING as u128) / y) as u64)
    }

    fun get_max_quote_from_base<T1, T2>(pool: &Pool<T1, T2>, price: u64, depth: u64, max_base: u64) : (u64, u64) {
        let filled_base_quantity =
            if (max_base >= depth) { depth }
            else { max_base };
        // If a bit is rounded down, the pool will take this as a fee.
        let (_, mut filled_quote_quantity) = unsafe_mul_round(filled_base_quantity, price);

        // if taker_commission = 0 due to underflow, round it up to 1
        let (is_round_down, mut taker_commission) = unsafe_mul_round(
            filled_quote_quantity,
            pool.taker_fee_rate(),
        );
        if (is_round_down) taker_commission = taker_commission + 1;

        // maker in bid side, decrease maker's locked quote asset, increase maker's available base asset
        filled_quote_quantity = filled_quote_quantity - taker_commission;
        (filled_base_quantity, filled_quote_quantity)
    }

    fun get_max_base_from_quote<T1, T2>(pool: &Pool<T1, T2>, price: u64, depth: u64, max_quote: u64, lot_size: u64) : (u64, u64) {
        // Calculate how much quote asset (maker_quote_quantity) is required, including the commission, to fill the maker order.
        let maker_quote_quantity_without_commission = clob_math::mul(
            depth,
            price,
        );
        let (is_round_down, mut taker_commission)  = unsafe_mul_round(
            maker_quote_quantity_without_commission,
            pool.taker_fee_rate(),
        );
        if (is_round_down)  taker_commission = taker_commission + 1;

        let maker_quote_quantity = maker_quote_quantity_without_commission + taker_commission;

        // Total base quantity filled.
        let mut filled_base_quantity: u64;
        // Total quote quantity filled, excluding commission and rebate.
        let filled_quote_quantity: u64;
        // Total quote quantity paid by taker.
        // filled_quote_quantity_without_commission * (FLOAT_SCALING + taker_fee_rate) = filled_quote_quantity
        let mut filled_quote_quantity_without_commission: u64;
        if (max_quote > maker_quote_quantity) {
            filled_quote_quantity = maker_quote_quantity;
            filled_base_quantity = depth;
        } else {
            // if not enough quote quantity to pay for taker commission, then no quantity will be filled
            (_, filled_quote_quantity_without_commission) = unsafe_div_round(
                max_quote,
                FLOAT_SCALING + pool.taker_fee_rate()
            );
            // filled_base_quantity = 0 is permitted since filled_quote_quantity_without_commission can be 0
            (_, filled_base_quantity) = unsafe_div_round(
                filled_quote_quantity_without_commission,
                price,
            );
            let filled_base_lot = filled_base_quantity / lot_size;
            filled_base_quantity = filled_base_lot * lot_size;
            //filled_quote_quantity_without_commission = 0 is permitted here since filled_base_quantity could be 0
            (_, filled_quote_quantity_without_commission) = unsafe_mul_round(
                filled_base_quantity,
                price,
            );
            // if taker_commission = 0 due to underflow, round it up to 1
            let (round_down, mut taker_commission) = unsafe_mul_round(
                filled_quote_quantity_without_commission,
                pool.taker_fee_rate(),
            );
            if (round_down) {
                taker_commission = taker_commission + 1;
            };
            filled_quote_quantity = filled_quote_quantity_without_commission + taker_commission;
        };

        (filled_quote_quantity, filled_base_quantity)
    }

    public fun predict_base_for_quote<T1, T2>(pool: &Pool<T1, T2>, amount: u64, lot_size: u64, clock: &Clock) {
        let max_price = (1u128 << 64 - 1 as u64);
        let (prices, depths) = clob::get_level2_book_status_bid_side(pool, 0, max_price, clock);
        let mut amount_left = amount;
        let mut output = 0;
        let mut i = vector::length(&prices);
        while(i > 0) {
            i = i - 1;
            let (used, max_out) = get_max_quote_from_base(
                pool, 
                *vector::borrow(&prices, i), 
                *vector::borrow(&depths, i), 
                amount_left
            );
            amount_left = amount_left - used;
            output = output + max_out;
            if(amount_left < lot_size) break;
        };
        event::emit( Event {
            amount_left,
            output,
        })
        
    }


    public fun predict_quote_for_base<T1, T2>(pool: &Pool<T1, T2>, amount: u64, lot_size: u64, clock: &Clock) {
        let max_price = (1u128 << 64 - 1 as u64);
        let (prices, depths) = clob::get_level2_book_status_ask_side(pool, 0, max_price, clock);

        let mut amount_left = amount;
        let mut output = 0;
        let mut i = 0;
        let length = vector::length(&prices);
        while(i < length) {   
            let price = *vector::borrow(&prices, i); 
            let (used, max_out) = get_max_base_from_quote(
                pool, 
                price, 
                *vector::borrow(&depths, i), 
                amount_left, 
                lot_size
            );
        
            amount_left = amount_left - used;
            output = output + max_out;
            let (_, left_base) = unsafe_div_round(amount_left, price);
            if (left_base < lot_size) break;
            i = i + 1;
        };
        
        event::emit( Event {
            amount_left,
            output,
        })
        
    }

    #[test]
    fun test() {
        let ctx = &mut tx_context.dummy();
        clob::create_pool(
            100,
            100,
            coin,
            ctx,
        );
    }   
}