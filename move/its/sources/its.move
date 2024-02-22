

module its::its {
    use std::string;
    use std::ascii::String;
    use std::type_name::{Self, TypeName};

    use sui::bag::{Self, Bag};
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::table::{Self, Table};
    use sui::coin::{TreasuryCap, CoinMetadata};
    use sui::transfer;

    use axelar::channel::Channel;

    use its::token_id::{Self, TokenId, UnregisteredTokenId};
    use its::address_tracker::{Self, InterchainAddressTracker};
    use its::coin_info::CoinInfo;
    use its::coin_management::CoinManagement;

    friend its::service;
    friend its::discovery;

    /// Trying to read a token that doesn't exist.
    const ENotFound: u64 = 0;

    public struct ITS has key {
        id: UID,
        channel: Channel,

        address_tracker: InterchainAddressTracker,

        unregistered_coin_types: Table<UnregisteredTokenId, TypeName>,
        unregistered_coin_info: Bag,

        registered_coin_types: Table<TokenId, TypeName>,
        registered_coins: Bag,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(ITS {
            id: object::new(ctx),
            channel: axelar::channel::new(ctx),

            address_tracker: address_tracker::new(
                ctx,
            ),

            registered_coins: bag::new(ctx),
            registered_coin_types: table::new(ctx),

            unregistered_coin_info: bag::new(ctx),
            unregistered_coin_types: table::new(ctx),
        });
    }

    public(friend) fun set_trusted_address(self: &mut ITS, chain_name: String, trusted_address: String) {
        address_tracker::set_trusted_address(&mut self.address_tracker, chain_name, trusted_address);
    }

    public fun get_unregistered_coin_type(
        self: &ITS, symbol: &String, decimals: u8
    ): &TypeName {
        let key = token_id::unregistered_token_id(symbol, decimals);

        assert!(self.unregistered_coin_types.contains(key), ENotFound);
        self.unregistered_coin_types.borrow(key)
    }

    public fun get_registered_coin_type(self: &ITS, token_id: TokenId): &TypeName {
        self.registered_coin_types.borrow(token_id)
    }

    public fun get_coin_data<T>(self: &ITS, token_id: TokenId): &CoinData<T> {
        self.registered_coins.borrow(token_id)
    }

    public fun get_coin_info<T>(self: &ITS, token_id: TokenId): &CoinInfo<T> {
        &get_coin_data<T>(self, token_id).coin_info
    }

    public fun token_name<T>(self: &ITS, token_id: TokenId): string::String {
        get_coin_info<T>(self, token_id).name()
    }

    public fun token_symbol<T>(self: &ITS, token_id: TokenId): String {
        get_coin_info<T>(self, token_id).symbol()
    }

    public fun token_decimals<T>(self: &ITS, token_id: TokenId): u8 {
        get_coin_info<T>(self, token_id).decimals()
    }

    public fun get_trusted_address(self: &ITS, chain_name: String): String {
        *self.address_tracker.get_trusted_address(chain_name)
    }

    public fun is_trusted_address(self: &ITS, source_chain: String, source_address: String): bool {
        self.address_tracker.is_trusted_address(source_chain, source_address)
    }

    // === Friend-only ===
    public(friend) fun channel(self: &ITS): &Channel {
        &self.channel
    }

    public(friend) fun channel_mut(self: &mut ITS): &mut Channel {
        &mut self.channel
    }

    public(friend) fun coin_management_mut<T>(self: &mut ITS, token_id: TokenId): &mut CoinManagement<T> {
        &mut coin_data_mut<T>(self, token_id).coin_management
    }

    public(friend) fun coin_data_mut<T>(self: &mut ITS, token_id: TokenId): &mut CoinData<T> {
        self.registered_coins.borrow_mut(token_id)
    }

    public(friend) fun add_unregistered_coin<T>(
        self: &mut ITS,
        token_id: UnregisteredTokenId,
        treasury_cap: TreasuryCap<T>,
        coin_metadata: CoinMetadata<T>
    ) {
        self.unregistered_coin_info.add(token_id, UnregisteredCoinData<T> {
            treasury_cap,
            coin_metadata,
        });

        let type_name = type_name::get<T>();
        add_unregistered_coin_type(self, token_id, type_name);
    }

    public(friend) fun remove_unregistered_coin<T>(
        self: &mut ITS, token_id: UnregisteredTokenId
    ): (TreasuryCap<T>, CoinMetadata<T>) {
        let UnregisteredCoinData<T> {
            treasury_cap,
            coin_metadata
        } = self.unregistered_coin_info.remove(token_id);

        remove_unregistered_coin_type(self, token_id);

        (treasury_cap, coin_metadata)
    }

    public(friend) fun add_registered_coin<T>(
        self: &mut ITS,
        token_id: TokenId,
        coin_management: CoinManagement<T>,
        coin_info: CoinInfo<T>,
    ) {
        self.registered_coins.add(token_id, CoinData<T> {
            coin_management,
            coin_info,
        });

        let type_name = type_name::get<T>();
        add_registered_coin_type(self, token_id, type_name);
    }

    // === Private ===

    fun add_unregistered_coin_type(self: &mut ITS, token_id: UnregisteredTokenId, type_name: TypeName) {
        self.unregistered_coin_types.add(token_id, type_name);
    }

    fun remove_unregistered_coin_type(self: &mut ITS, token_id: UnregisteredTokenId): TypeName {
        self.unregistered_coin_types.remove(token_id)
    }

    fun add_registered_coin_type(self: &mut ITS, token_id: TokenId, type_name: TypeName) {
        self.registered_coin_types.add(token_id, type_name);
    }

    #[allow(unused_function)]
    fun remove_registered_coin_type(self: &mut ITS, token_id: TokenId): TypeName {
        self.registered_coin_types.remove(token_id)
    }
}
