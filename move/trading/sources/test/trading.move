module trading::trading {
    use deepbook::clob_v2::{Self as clob, Pool};
    use deepbook::custodian_v2::{AccountCap};
    use sui::coin::{Self, TreasuryCap};
    use sui::clock::Clock;
    use sui::event;

    public struct Storage<phantom T1, phantom T2> has key {
        id: UID,
        account_cap: AccountCap,
        account_cap_trader: AccountCap,
        treasury_cap_base: TreasuryCap<T1>,
        treasury_cap_quote: TreasuryCap<T2>,
    }

    public struct Event has copy, drop {
        amount_base: u64,
        amount_quote: u64,
    }

    public struct Balances has copy, drop {
        base_avail: u64,
        base_locked: u64,
        quote_avail: u64,
        quote_locked: u64,
    }


    public fun initialize<T1, T2>(
        treasury_cap_base: TreasuryCap<T1>,
        treasury_cap_quote: TreasuryCap<T2>,
        ctx: &mut TxContext,
    ) {
        transfer::share_object(Storage<T1, T2>{
            id: object::new(ctx),
            account_cap: clob::create_account(ctx),
            account_cap_trader: clob::create_account(ctx),
            treasury_cap_base,
            treasury_cap_quote,
        });
    }

    public fun add_listing<T1, T2>(this: &mut Storage<T1, T2>, pool: &mut Pool<T1, T2>, price: u64, quantity: u64, is_bid: bool, clock: &Clock, ctx: &mut TxContext) {
        if(is_bid) {
            let quote_coin = this.treasury_cap_quote.mint(quantity, ctx);
            pool.deposit_quote(quote_coin, &this.account_cap);
        } else {
            let base_coin = this.treasury_cap_base.mint(quantity, ctx);
            pool.deposit_base(base_coin, &this.account_cap);
        };
        pool.place_limit_order(
            0,
            price,
            quantity,
            0,
            is_bid,
            10000000000000000000,
            3,
            clock,
            &this.account_cap,
            ctx,
        );
        balances(this, pool);
    }

    public fun swap_base<T1, T2>(this: &mut Storage<T1, T2>, pool: &mut Pool<T1, T2>, quantity: u64, clock: &Clock, ctx: &mut TxContext) {
        let (base_coin, quote_coin, _) = pool.swap_exact_base_for_quote(
            0,
            &this.account_cap_trader,
            quantity,
            this.treasury_cap_base.mint(quantity, ctx),
            coin::zero<T2>(ctx),
            clock,
            ctx,
        );
        event::emit( Event {
            amount_base: this.treasury_cap_base.burn(base_coin),
            amount_quote: this.treasury_cap_quote.burn(quote_coin),
        })
    }

    public fun swap_quote<T1, T2>(this: &mut Storage<T1, T2>, pool: &mut Pool<T1, T2>, quantity: u64, clock: &Clock, ctx: &mut TxContext) {
        let (base_coin, quote_coin, _) = pool.swap_exact_quote_for_base(
            0,
            &this.account_cap_trader,
            quantity,
            clock,
            this.treasury_cap_quote.mint(quantity, ctx),
            ctx,
        );
        event::emit( Event {
            amount_base: this.treasury_cap_base.burn(base_coin),
            amount_quote: this.treasury_cap_quote.burn(quote_coin),
        });
        balances(this, pool);
    }

    public fun balances<T1, T2>(this: &Storage<T1, T2>, pool: &Pool<T1, T2>) {
        let (base_avail, base_locked, quote_avail, quote_locked) = pool.account_balance(&this.account_cap);
        event::emit( Balances {
            base_avail,
            base_locked,
            quote_avail,
            quote_locked,
        });
    }
}
