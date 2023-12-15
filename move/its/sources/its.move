//
//

module its::token_service {
    use std::type_name;
    use std::string::{Self, String};

    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::TxContext;
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::bag::{Self, Bag};
    use sui::hash::blake2b256;
    use sui::transfer;
    use sui::balance;
    use sui::bcs;

    const SUI_PREFIX: vector<u8> = b"sui_token";

    /// Trying to register a native coin that is already registered with the
    /// same `token_id`.
    const EAlreadyKnown: u64 = 0;
    /// Trying to send a native coin that is not registered.
    const EUnknownToken: u64 = 1;

    /// `TokenService` is a service that manages tokens and their IDs.
    ///
    struct TokenService has key {
        id: UID,

        // TODO: link to the Channel
        // channel: Channel,

        /// TODO: turn into a BigSet as soon as it's implemented;
        /// TODO: single object size limit is 256KB, and `VecSet` is limited
        /// TODO: token_id MUST include TypeName in its generation
        native_token_ids: VecSet<String>,
        /// Bag that stores balances of native coins indexed by `NativeTokenKey`.
        native_assets: Bag,
    }

    /// DF key for `native_assets` Bag.
    struct NativeTokenKey<phantom T> has copy, store, drop { token_id: String }

    /// Register a native coin.
    /// Anyone can do it, right?
    public fun register_native_coin<T>(
        self: &mut TokenService,
        decimals: u8,
        symbol: String,
        name: String,
        _ctx: &mut TxContext
    ) {
        let token_id = token_id<T>(decimals, symbol, name);
        let token_key = NativeTokenKey<T> { token_id };

        assert!(!vec_set::contains(&self.native_token_ids, &token_id), EAlreadyKnown);
        assert!(!bag::contains(&self.native_assets, token_key), EAlreadyKnown);

        vec_set::insert(&mut self.native_token_ids, token_id);
        bag::add(&mut self.native_assets, token_key, balance::zero<T>());

        // emit an event? or we can read the `native_assets` Bag always
    }

    #[allow(unused_function)]
    /// Send a Sui-native Coin by locking it in the `TokenService`.
    /// This function can be kept private and only do business logic of TokenSerice,
    /// message passing and verification can be done as a higher-level function.
    fun send_native<T>(
        self: &mut TokenService,
        coin: Coin<T>,
        token_id: String,
        _ctx: &mut TxContext
    ) {
        let token_key = NativeTokenKey<T> { token_id };

        assert!(vec_set::contains(&self.native_token_ids, &token_id), EUnknownToken);
        assert!(bag::contains(&self.native_assets, token_key), EUnknownToken);

        // put the Coin into the TokenService balances Bag
        coin::put(bag::borrow_mut(&mut self.native_assets, token_key), coin);

        // emit an event? or we can read the `native_assets` Bag always
        // use axelar events system for this
    }

    #[allow(unused_function)]
    /// Receive a Sui-native Coin by unlocking it from the `TokenService`.
    /// TODO: to be triggered when a message is received.
    fun receive_native<T>(
        self: &mut TokenService,
        token_id: String,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        let token_key = NativeTokenKey<T> { token_id };

        assert!(vec_set::contains(&self.native_token_ids, &token_id), EUnknownToken);
        assert!(bag::contains(&self.native_assets, token_key), EUnknownToken);

        coin::take(bag::borrow_mut(&mut self.native_assets, token_key), amount, ctx)
    }

    /// Generate a `token_id` for a Sui Native token.
    /// MUST include `TypeName` of `T` so there's no collision between different types.
    fun token_id<T>(
        decimals: u8,
        symbol: String,
        name: String
    ): String {
        let source = bcs::to_bytes(&vector[
            SUI_PREFIX,
            bcs::to_bytes(&decimals),
            bcs::to_bytes(&symbol),
            bcs::to_bytes(&name),
            bcs::to_bytes(&type_name::get<T>()),
        ]);

        string::utf8(blake2b256(&source))
    }

    // create and share the `TokenService`
    fun init(ctx: &mut TxContext) {
        transfer::share_object(TokenService {
            id: object::new(ctx),
            native_token_ids: vec_set::empty(),
            native_assets: bag::new(ctx),
        })
    }
}
