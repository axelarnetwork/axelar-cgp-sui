

module interchain_token_service::storage {
    use std::string;
    use std::ascii::{String};
    use std::type_name::{Self, TypeName};

    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::dynamic_field as df;
    use sui::table::{Self, Table};
    use sui::coin::{TreasuryCap, CoinMetadata};

    use axelar::channel::{Self, Channel};

    use interchain_token_service::token_id::{Self, TokenId, UnregisteredTokenId};
    use interchain_token_service::interchain_address_tracker::{Self, InterchainAddressTracker};
    use interchain_token_service::coin_info::{Self, CoinInfo};
    use interchain_token_service::coin_management::{CoinManagement};

    friend interchain_token_service::service;
    
    struct CoinData<phantom T> has store {
        coin_management: CoinManagement<T>,
        coin_info: CoinInfo<T>,
    }

    struct UnregisteredCoinData<phantom T> has store {
        treasury_cap: TreasuryCap<T>,
        coin_metadata: CoinMetadata<T>,
    }

    struct ITS has key {
        id: UID,
        channel: Channel,

        address_tracker: InterchainAddressTracker,
        
        unregistered_coin_types: Table<UnregisteredTokenId, TypeName>,
        unregistered_coin_info: UID,

        registered_coin_types: Table<TokenId, TypeName>,
        registered_coins: UID,
    }

    fun init(ctx: &mut TxContext) {
        let its = get_singleton_its(ctx);
        transfer::share_object(its);
    }

    public (friend) fun get_singleton_its(ctx: &mut TxContext) : (ITS) {
        let self = ITS {
            id: object::new(ctx),
            channel: channel::create_channel(ctx),

            address_tracker: interchain_address_tracker::new(ctx),

            registered_coins: object::new(ctx),
            registered_coin_types: table::new<TokenId, TypeName>(ctx),

            unregistered_coin_info: object::new(ctx),
            unregistered_coin_types: table::new<UnregisteredTokenId, TypeName>(ctx),
        };
        self
    }

    public fun borrow_unregistered_coin_type(self: &ITS, symbol: &String, decimals: &u8): &TypeName {
        table::borrow(&self.unregistered_coin_types, token_id::unregistered_token_id(symbol, decimals))
    }

    fun add_unregistered_coin_type(self: &mut ITS, token_id: UnregisteredTokenId, type_name: TypeName) {
        table::add(&mut self.unregistered_coin_types, token_id, type_name);
    }

    fun remove_unregistered_coin_type(self: &mut ITS, token_id: UnregisteredTokenId) : TypeName {
        table::remove(&mut self.unregistered_coin_types, token_id)
    }

    public fun borrow_registered_coin_type(self: &ITS, token_id: TokenId): &TypeName {
        table::borrow(&self.registered_coin_types, token_id)
    }

    fun add_registered_coin_type(self: &mut ITS, token_id: TokenId, type_name: TypeName) {
        table::add(&mut self.registered_coin_types, token_id, type_name);
    }

    #[allow(unused_function)]
    fun remove_registered_coin_type(self: &mut ITS, token_id: TokenId) : TypeName {
        table::remove(&mut self.registered_coin_types, token_id)
    }

    public (friend) fun add_unregistered_coin<T>(self: &mut ITS, token_id: UnregisteredTokenId, treasury_cap: TreasuryCap<T>, coin_metadata: CoinMetadata<T>) {
        df::add<UnregisteredTokenId, UnregisteredCoinData<T>>(&mut self.unregistered_coin_info, token_id, UnregisteredCoinData<T> {
            treasury_cap,
            coin_metadata,
        });
        let type_name = type_name::get<T>();
        add_unregistered_coin_type(self, token_id, type_name);
    }

    public (friend) fun remove_unregistered_coin<T>(self: &mut ITS, token_id: UnregisteredTokenId): (TreasuryCap<T>, CoinMetadata<T>) {
        let UnregisteredCoinData<T> { treasury_cap, coin_metadata } = df::remove<UnregisteredTokenId, UnregisteredCoinData<T>>(&mut self.unregistered_coin_info, token_id);
        remove_unregistered_coin_type(self, token_id);
        (treasury_cap, coin_metadata)
    }

    public (friend) fun add_registered_coin<T>(
        self: &mut ITS, 
        token_id: TokenId, 
        coin_management: CoinManagement<T>, 
        coin_info: CoinInfo<T>,
    ) {
        df::add<TokenId, CoinData<T>>(&mut self.registered_coins, token_id, CoinData<T> {
            coin_management,
            coin_info,
        });
        let type_name = type_name::get<T>();
        add_registered_coin_type(self, token_id, type_name);
    }

    public fun borrow_coin_data<T>(self: &ITS, token_id: TokenId) : &CoinData<T> {
        df::borrow<TokenId, CoinData<T>>(&self.registered_coins, token_id)
    }

    public (friend) fun borrow_mut_coin_data<T>(self: &mut ITS, token_id: TokenId) : &mut CoinData<T> {
        df::borrow_mut<TokenId, CoinData<T>>(&mut self.registered_coins, token_id)
    }

    public fun borrow_coin_info<T>(self: &ITS, token_id: TokenId) : &CoinInfo<T> {
        let registered_coin = borrow_coin_data<T>(self, token_id);
        &registered_coin.coin_info
    }

    public (friend) fun borrow_mut_coin_management<T>(self: &mut ITS, token_id: TokenId) : &mut CoinManagement<T> {
        let registered_coin = borrow_mut_coin_data<T>(self, token_id);
        &mut registered_coin.coin_management
    }

    public fun token_name<T>(self: &ITS, token_id: TokenId) : string::String {
        let coin_info = borrow_coin_info<T>(self, token_id);
        coin_info::name<T>(coin_info)
    }

    public fun token_symbol<T>(self: &ITS, token_id: TokenId) : String {
        let coin_info = borrow_coin_info<T>(self, token_id);
        coin_info::symbol<T>(coin_info)
    }

    public fun token_decimals<T>(self: &ITS, token_id: TokenId) : u8 {
        let coin_info = borrow_coin_info<T>(self, token_id);
        coin_info::decimals<T>(coin_info)
    }

    public (friend) fun borrow_mut_channel(self: &mut ITS): &mut Channel {
        &mut self.channel
    }

    public fun get_trusted_address(self: &ITS, chain_name: String): String {
        *interchain_address_tracker::borrow_trusted_address(&self.address_tracker, chain_name)
    }

    public fun is_trusted_address(self: &ITS, source_chain: String, source_address: String): bool {
        &source_address == interchain_address_tracker::borrow_trusted_address(&self.address_tracker, source_chain)
    }
}