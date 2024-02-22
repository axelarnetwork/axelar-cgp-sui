

module its::storage {
    use std::string;
    use std::ascii::{Self, String};
    use std::type_name::{Self, TypeName};

    use sui::bag::{Self, Bag};
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::table::{Self, Table};
    use sui::coin::{TreasuryCap, CoinMetadata};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::transfer;

    use axelar::channel::{Self, Channel};

    use its::token_id::{Self, TokenId, UnregisteredTokenId};
    use its::interchain_address_tracker::{Self, InterchainAddressTracker};
    use its::coin_info::{Self, CoinInfo};
    use its::coin_management::CoinManagement;

    friend its::service;
    friend its::discovery;

    /// Trying to read a token that doesn't exist.
    const ENotFound: u64 = 0;

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
        unregistered_coin_info: Bag,

        registered_coin_types: Table<TokenId, TypeName>,
        registered_coins: Bag,

        upgrade_cap: UpgradeCap,
    }

    public fun give_upgrade_cap(upgrade_cap: UpgradeCap, ctx: &mut TxContext) {
        transfer::share_object(ITS {
            id: object::new(ctx),
            channel: channel::create_channel(ctx),

            address_tracker: interchain_address_tracker::new(
                ctx,
                ascii::string(b"Axelar"),
                ascii::string(b"0x..."),
            ),

            registered_coins: bag::new(ctx),
            registered_coin_types: table::new(ctx),

            unregistered_coin_info: bag::new(ctx),
            unregistered_coin_types: table::new(ctx),

            upgrade_cap,
        });
    }

    public(friend) fun set_trusted_address(self: &mut ITS, chain_name: String, trusted_address: String) {
        interchain_address_tracker::set_trusted_address(&mut self.address_tracker, chain_name, trusted_address);
    }

    public fun borrow_unregistered_coin_type(
        self: &ITS, symbol: &String, decimals: u8
    ): &TypeName {
        let key = token_id::unregistered_token_id(symbol, decimals);

        assert!(table::contains(&self.unregistered_coin_types, key), ENotFound);
        table::borrow(&self.unregistered_coin_types, key)
    }

    public fun borrow_registered_coin_type(self: &ITS, token_id: TokenId): &TypeName {
        table::borrow(&self.registered_coin_types, token_id)
    }

    public fun borrow_coin_data<T>(self: &ITS, token_id: TokenId) : &CoinData<T> {
        bag::borrow(&self.registered_coins, token_id)
    }

    public fun borrow_coin_info<T>(self: &ITS, token_id: TokenId) : &CoinInfo<T> {
        &borrow_coin_data<T>(self, token_id).coin_info
    }

    public fun token_name<T>(self: &ITS, token_id: TokenId) : string::String {
        coin_info::name<T>(borrow_coin_info<T>(self, token_id))
    }

    public fun token_symbol<T>(self: &ITS, token_id: TokenId) : String {
        coin_info::symbol<T>(borrow_coin_info<T>(self, token_id))
    }

    public fun token_decimals<T>(self: &ITS, token_id: TokenId) : u8 {
        coin_info::decimals<T>(borrow_coin_info<T>(self, token_id))
    }

    public fun get_trusted_address(self: &ITS, chain_name: String): String {
        *interchain_address_tracker::get_trusted_address(&self.address_tracker, chain_name)
    }

    public fun is_trusted_address(self: &ITS, source_chain: String, source_address: String): bool {
        interchain_address_tracker::is_trusted_address(&self.address_tracker, source_chain, source_address)
    }

    public fun is_axelar_governance(self: &ITS, source_chain: String, source_address: String): bool {
        interchain_address_tracker::is_axelar_governance(&self.address_tracker, source_chain, source_address)
    }

    // === Friend-only ===
    public(friend) fun channel(self: &ITS): &Channel {
        &self.channel
    }

    public(friend) fun channel_mut(self: &mut ITS): &mut Channel {
        &mut self.channel
    }

    public(friend) fun coin_management_mut<T>(self: &mut ITS, token_id: TokenId) : &mut CoinManagement<T> {
        &mut coin_data_mut<T>(self, token_id).coin_management
    }

    public(friend) fun coin_data_mut<T>(self: &mut ITS, token_id: TokenId) : &mut CoinData<T> {
        bag::borrow_mut(&mut self.registered_coins, token_id)
    }

    public(friend) fun add_unregistered_coin<T>(
        self: &mut ITS,
        token_id: UnregisteredTokenId,
        treasury_cap: TreasuryCap<T>,
        coin_metadata: CoinMetadata<T>
    ) {
        bag::add(
            &mut self.unregistered_coin_info,
            token_id,
            UnregisteredCoinData<T> {
                treasury_cap,
                coin_metadata,
            }
        );

        let type_name = type_name::get<T>();
        add_unregistered_coin_type(self, token_id, type_name);
    }

    public(friend) fun remove_unregistered_coin<T>(
        self: &mut ITS, token_id: UnregisteredTokenId
    ): (TreasuryCap<T>, CoinMetadata<T>) {
        let UnregisteredCoinData<T> {
            treasury_cap,
            coin_metadata
        } = bag::remove(&mut self.unregistered_coin_info, token_id);

        remove_unregistered_coin_type(self, token_id);

        (treasury_cap, coin_metadata)
    }

    public(friend) fun add_registered_coin<T>(
        self: &mut ITS,
        token_id: TokenId,
        coin_management: CoinManagement<T>,
        coin_info: CoinInfo<T>,
    ) {
        bag::add(&mut self.registered_coins, token_id, CoinData<T> {
            coin_management,
            coin_info,
        });

        let type_name = type_name::get<T>();
        add_registered_coin_type(self, token_id, type_name);
    }

    public(friend) fun authorize_upgrade(
        self: &mut ITS, 
        policy: u8,
        digest: vector<u8>
    ): UpgradeTicket {
        package::authorize_upgrade(&mut self.upgrade_cap, policy, digest)
    }


    public(friend) fun commit_upgrade(
        self: &mut ITS,
        receipt: UpgradeReceipt,
    ) {
        package::commit_upgrade(&mut self.upgrade_cap, receipt)
    }

    // === Private ===

    fun add_unregistered_coin_type(self: &mut ITS, token_id: UnregisteredTokenId, type_name: TypeName) {
        table::add(&mut self.unregistered_coin_types, token_id, type_name);
    }

    fun remove_unregistered_coin_type(self: &mut ITS, token_id: UnregisteredTokenId): TypeName {
        table::remove(&mut self.unregistered_coin_types, token_id)
    }

    fun add_registered_coin_type(self: &mut ITS, token_id: TokenId, type_name: TypeName) {
        table::add(&mut self.registered_coin_types, token_id, type_name);
    }

    #[allow(unused_function)]
    fun remove_registered_coin_type(self: &mut ITS, token_id: TokenId): TypeName {
        table::remove(&mut self.registered_coin_types, token_id)
    }
}
