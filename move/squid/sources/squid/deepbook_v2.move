module squid::deepbook_v2 {
    use std::type_name;
    use std::ascii;

    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::bcs::{Self, BCS};

    use deepbook::clob_v2::{Self as clob, Pool};
    use deepbook::custodian_v2::{Self as custodian};
    use deepbook::math as clob_math;

    use axelar::discovery::{Self, MoveCall};

    use squid::swap_info::{SwapInfo};
    use squid::squid::Squid;

    const FLOAT_SCALING_U128: u128 = 1_000_000_000;
    const FLOAT_SCALING: u64 = 1_000_000_000;

    const SWAP_TYPE: u8 = 1;
    
    const EWrongSwapType: u64 = 0;
    const EWrongPool: u64 = 1;
    const EWrongCoinType: u64 = 2;
    const ENotEnoughOutput: u64 = 3;

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

    public fun predict_base_for_quote<T1, T2>(pool: &Pool<T1, T2>, amount: u64, lot_size: u64, clock: &Clock): (u64, u64) {
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
        (amount_left, output)
        
    }

    public fun predict_quote_for_base<T1, T2>(pool: &Pool<T1, T2>, amount: u64, lot_size: u64, clock: &Clock): (u64, u64) {
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
        
        (amount_left, output)
    }

    public fun estimate<T1, T2>(self: &mut SwapInfo, pool: &Pool<T1, T2>, clock: &Clock) {
        let data = self.get_data_estimating();
        if(vector::length(&data) == 0) return;

        let mut bcs = bcs::new(data);

        assert!(bcs.peel_u8() == SWAP_TYPE, EWrongSwapType);

        assert!(bcs.peel_address() == object::id_address(pool), EWrongPool);

        let has_base = bcs.peel_bool();
        let min_output = bcs.peel_u64();

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T1>().into_string().into_bytes(),
            EWrongCoinType,
        );

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T2>().into_string().into_bytes(),
            EWrongCoinType,
        );

        let lot_size = bcs.peel_u64();
        let should_sweep = bcs.peel_bool();
        if(has_base) {
            let (amount_left, output) = predict_base_for_quote(
                pool,
                // these are run in sequence before anything is done with balances, so `get_estimate` is the correct function to use.
                self.coin_bag().get_estimate<T1>(),
                lot_size,
                clock,
            );
            if(min_output > output) {
                self.skip_swap();
                return
            };
            if(!should_sweep) self.coin_bag().store_estimate<T1>(amount_left);
            self.coin_bag().store_estimate<T2>(output);
        } else {
            let (amount_left, output) = predict_quote_for_base(
                pool,
                self.coin_bag().get_estimate<T2>(),
                lot_size,
                clock,
            );
            if(min_output > output) {
                self.skip_swap();
                return
            };
            if(!should_sweep) self.coin_bag().store_estimate<T2>(amount_left);
            self.coin_bag().store_estimate<T1>(output);
        }
    }

    public fun swap<T1, T2>(self: &mut SwapInfo, pool: &mut Pool<T1, T2>, squid: &mut Squid, clock: &Clock, ctx: &mut TxContext) {
        let data = self.get_data_swapping();
        if(vector::length(&data) == 0) return;
        let mut bcs = bcs::new(data);

        assert!(bcs.peel_u8() == SWAP_TYPE, EWrongSwapType);

        assert!(bcs.peel_address() == object::id_address(pool), EWrongPool);

        let has_base = bcs.peel_bool();
        let min_output = bcs.peel_u64();

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T1>().into_string().into_bytes(),
            EWrongCoinType,
        );

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T2>().into_string().into_bytes(),
            EWrongCoinType,
        );

        let lot_size = bcs.peel_u64();
        let should_sweep = bcs.peel_bool();
        if(has_base) {
            let mut base_balance = self.coin_bag().get_balance<T1>().destroy_some();
            let leftover = base_balance.value() % lot_size;
            if(leftover > 0) {
                if(should_sweep) {
                    squid.coin_bag().store_balance<T1>(
                        base_balance.split(leftover)
                    );
                } else {
                    self.coin_bag().store_balance<T1>(
                        base_balance.split(leftover),
                    );
                };
            };
            let (base_coin, quote_coin) = swap_base(
                pool,
                coin::from_balance(base_balance, ctx),
                clock,
                ctx,
            );
            assert!(min_output <= quote_coin.value(), ENotEnoughOutput);    
            base_coin.destroy_zero();
            self.coin_bag().store_balance<T2>(quote_coin.into_balance());
        } else {
            let quote_balance = self.coin_bag().get_balance<T2>().destroy_some();
            let (base_coin, quote_coin) = swap_quote(
                pool,
                coin::from_balance(quote_balance, ctx),
                clock,
                ctx,
            );
            assert!(min_output <= base_coin.value(), ENotEnoughOutput);    
            self.coin_bag().store_balance<T1>(base_coin.into_balance());
            if(should_sweep) {
                squid.coin_bag().store_balance<T2>(quote_coin.into_balance());
            } else {
                self.coin_bag().store_balance<T2>(quote_coin.into_balance());
            };
        }
    }

    public(package) fun get_estimate_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>): MoveCall {
        let mut pool_arg = vector[0];
        vector::append(&mut pool_arg, bcs.peel_address().to_bytes());

        let _has_base = bcs.peel_bool();
        let _min_output = bcs.peel_u64();

        let type_base = ascii::string(bcs.peel_vec_u8());
        let type_quote = ascii::string(bcs.peel_vec_u8());

        discovery::new_move_call(
                discovery::new_function(
                    package_id,
                    ascii::string(b"deepbook_v2"),
                    ascii::string(b"estimate"),
                ),
                vector[
                    swap_info_arg,
                    pool_arg,
                    vector[0, 6],
                ],
                vector[type_base, type_quote],
            )
    }

    public(package) fun get_swap_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>, squid_arg: vector<u8>): MoveCall {
        let mut pool_arg = vector[0];
        vector::append(&mut pool_arg, bcs.peel_address().to_bytes());

        let _has_base = bcs.peel_bool();
        let _min_output = bcs.peel_u64();

        let type_base = ascii::string(bcs.peel_vec_u8());
        let type_quote = ascii::string(bcs.peel_vec_u8());       

        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"deepbook_v2"),
                ascii::string(b"swap"),
            ),
            vector[
                swap_info_arg,
                pool_arg,
                squid_arg,
                vector[0, 6],
            ],
            vector[type_base, type_quote] ,
        )
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