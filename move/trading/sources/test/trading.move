module trading::trading {
    use deepbook::clob_v2::{Self as clob, Pool};
    use deepbook::custodian_v2::{Self as custodian};
    use deepbook::order_query::{Self};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event;

    public struct Event has copy, drop {
        tick_level: u64,
        quantity: u64,
        timestamp: u64,
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

    public fun predict_base<T1, T2>(pool: &mut Pool<T1, T2>, amount: u64, clock: &Clock) {
        let page = order_query::iter_bids(pool, option::none<u64>(), option::none<u64>(), option::none<u64>(), option::none<u64>(), true);
        let order = vector::borrow(page.orders(), 0);
        event::emit(Event {
            tick_level: order.tick_level(),
            quantity: order.quantity(),
            timestamp: order.expire_timestamp(),
        });
        
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