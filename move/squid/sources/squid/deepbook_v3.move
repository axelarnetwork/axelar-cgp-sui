module squid::deepbook_v3 {
    use std::type_name;
    use std::ascii::{Self, String};

    use sui::clock::Clock;
    use sui::bcs::{Self, BCS};

    use deepbook::pool::Pool;
    use token::deep::DEEP;

    use axelar_gateway::discovery::{Self, MoveCall};

    use squid::swap_info::{SwapInfo};
    use squid::squid::Squid;

    const EWrongSwapType: u64 = 0;
    const EWrongPool: u64 = 1;
    const EWrongCoinType: u64 = 2;

    const SWAP_TYPE: u8 = 1;

    public struct DeepbookV3SwapData has drop {
        swap_type: u8,
        pool_id: address,
        has_base: bool,
        min_output: u64,
        base_type: String,
        quote_type: String,
        deep_required: u64,
        should_sweep: bool,
    }

    /// Estimate the output of a swap. If the output is less than the minimum output, the swap is skipped.
    /// If the swap is not skipped, the estimate is stored in the coin bag.
    public fun estimate<B, Q>(self: &mut SwapInfo, pool: &Pool<B, Q>, clock: &Clock) {
        let data = self.get_data_swapping();
        if (data.length() == 0) return;
        let swap_data = peel_swap_data(data);

        assert!(swap_data.swap_type == SWAP_TYPE, EWrongSwapType);
        assert!(swap_data.pool_id == object::id_address(pool), EWrongPool);
        assert!(
            &swap_data.base_type == &type_name::get<B>().into_string(),
            EWrongCoinType,
        );
        assert!(
            &swap_data.quote_type == &type_name::get<Q>().into_string(),
            EWrongCoinType,
        );

        if (swap_data.has_base) {
            let (amount_left, output, _deep_required) = pool.get_quote_quantity_out(
                self.coin_bag().get_estimate<B>(),
                clock
            );
            if (swap_data.min_output > output) {
                self.skip_swap();
                return
            };
            if (!swap_data.should_sweep) self.coin_bag().store_estimate<B>(amount_left);
            self.coin_bag().store_estimate<Q>(output);
        } else {
            let (amount_left, output, _deep_required) = pool.get_base_quantity_out(
                self.coin_bag().get_estimate<Q>(),
                clock
            );
            if (swap_data.min_output > output) {
                self.skip_swap();
                return
            };
            if (!swap_data.should_sweep) self.coin_bag().store_estimate<Q>(amount_left);
            self.coin_bag().store_estimate<B>(output);
        }
    }

    /// Perform a swap. First, check how much DEEP is required to perform the swap.
    /// Then, get that amount of DEEP from squid. Use it to swap the entire amount
    /// of the base or quote currency. Store any remaining DEEP back in squid.
    public fun swap<B, Q>(
        self: &mut SwapInfo,
        pool: &mut Pool<B, Q>,
        squid: &mut Squid,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let data = self.get_data_swapping();
        if (data.length() == 0) return;
        let swap_data = peel_swap_data(data);

        assert!(swap_data.swap_type == SWAP_TYPE, EWrongSwapType);
        assert!(swap_data.pool_id == object::id_address(pool), EWrongPool);
        assert!(
            &swap_data.base_type == &type_name::get<B>().into_string(),
            EWrongCoinType,
        );
        assert!(
            &swap_data.quote_type == &type_name::get<Q>().into_string(),
            EWrongCoinType,
        );

        if (swap_data.has_base) {
            let (_, _, deep_required) = pool.get_quote_quantity_out(
                self.coin_bag().get_estimate<B>(),
                clock
            );
            let deep_in = squid.coin_bag().get_exact_balance<DEEP>(deep_required).destroy_some().into_coin(ctx);
            let base_in = self.coin_bag().get_balance<B>().destroy_some().into_coin(ctx);

            let (base_out, quote_out, deep_out) = pool.swap_exact_base_for_quote<B, Q>(
                base_in,
                deep_in,
                swap_data.min_output,
                clock,
                ctx
            );

            self.coin_bag().store_balance(quote_out.into_balance());
            squid.coin_bag().store_balance(deep_out.into_balance());
            if (swap_data.should_sweep) {
                squid.coin_bag().store_balance(base_out.into_balance());
            } else {
                self.coin_bag().store_balance(base_out.into_balance());
            };
            
        } else {
            let (_, _, deep_required) = pool.get_base_quantity_out(
                self.coin_bag().get_estimate<Q>(),
                clock
            );
            let deep_in = squid.coin_bag().get_exact_balance<DEEP>(deep_required).destroy_some().into_coin(ctx);
            let quote_in = self.coin_bag().get_balance<Q>().destroy_some().into_coin(ctx);

            let (quote_out, base_out, deep_out) = pool.swap_exact_quote_for_base<B, Q>(
                quote_in,
                deep_in,
                swap_data.min_output,
                clock,
                ctx
            );

            self.coin_bag().store_balance(base_out.into_balance());
            squid.coin_bag().store_balance(deep_out.into_balance());
            if (swap_data.should_sweep) {
                squid.coin_bag().store_balance(quote_out.into_balance());
            } else {
                self.coin_bag().store_balance(quote_out.into_balance());
            };
        }
    }

    public(package) fun get_estimate_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>): MoveCall {
        let mut pool_arg = vector[0];
        pool_arg.append(bcs.peel_address().to_bytes());

        let _has_base = bcs.peel_bool();
        let _min_output = bcs.peel_u64();

        let type_base = ascii::string(bcs.peel_vec_u8());
        let type_quote = ascii::string(bcs.peel_vec_u8());

        discovery::new_move_call(
                discovery::new_function(
                    package_id,
                    ascii::string(b"deepbook_v3"),
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
        pool_arg.append(bcs.peel_address().to_bytes());

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

    fun peel_swap_data(data: vector<u8>): DeepbookV3SwapData {
        let mut bcs = bcs::new(data);
        DeepbookV3SwapData {
            swap_type: bcs.peel_u8(),
            pool_id: bcs.peel_address(),
            has_base: bcs.peel_bool(),
            min_output: bcs.peel_u64(),
            base_type: ascii::string(bcs.peel_vec_u8()),
            quote_type: ascii::string(bcs.peel_vec_u8()),
            deep_required: bcs.peel_u64(),
            should_sweep: bcs.peel_bool(),
        }
    }
}