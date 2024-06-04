

module its::its {
    use std::string;
    use std::ascii::String;
    use std::type_name::{Self, TypeName};

    use sui::bag::{Self, Bag};
    use sui::table::{Self, Table};
    use sui::coin::{TreasuryCap, CoinMetadata};

    use axelar_gateway::channel::Channel;
    use axelar_gateway::discovery::RelayerDiscovery;

    use its::token_id::{Self, TokenId, UnregisteredTokenId};
    use its::address_tracker::{Self, InterchainAddressTracker};
    use its::coin_info::CoinInfo;
    use its::coin_management::CoinManagement;

    /// Trying to read a token that doesn't exist.
    const ENotFound: u64 = 0;
    const EUnregisteredCoin: u64 = 1;

    public struct ITS has key {
        id: UID,
        channel: Channel,

        address_tracker: InterchainAddressTracker,

        unregistered_coin_types: Table<UnregisteredTokenId, TypeName>,
        unregistered_coin_info: Bag,

        registered_coin_types: Table<TokenId, TypeName>,
        registered_coins: Bag,

        relayer_discovery_id: ID,
    }

    public struct CoinData<phantom T> has store {
        coin_management: CoinManagement<T>,
        coin_info: CoinInfo<T>,
    }

    public struct UnregisteredCoinData<phantom T> has store {
        treasury_cap: TreasuryCap<T>,
        coin_metadata: CoinMetadata<T>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(ITS {
            id: object::new(ctx),
            channel: axelar_gateway::channel::new(ctx),

            address_tracker: address_tracker::new(
                ctx,
            ),

            registered_coins: bag::new(ctx),
            registered_coin_types: table::new(ctx),

            unregistered_coin_info: bag::new(ctx),
            unregistered_coin_types: table::new(ctx),

            relayer_discovery_id: object::id_from_address(@0x0),
        });
    }

    public(package) fun set_relayer_discovery_id(self: &mut ITS, relayer_discovery: &RelayerDiscovery) {
        self.relayer_discovery_id = object::id(relayer_discovery);
    }

    public(package) fun relayer_discovery_id(self: &ITS): ID {
        self.relayer_discovery_id
    }

    public(package) fun set_trusted_address(self: &mut ITS, chain_name: String, trusted_address: String) {
        self.address_tracker.set_trusted_address(chain_name, trusted_address);
    }

    public fun get_unregistered_coin_type(
        self: &ITS, symbol: &String, decimals: u8
    ): &TypeName {
        let key = token_id::unregistered_token_id(symbol, decimals);

        assert!(self.unregistered_coin_types.contains(key), ENotFound);
        &self.unregistered_coin_types[key]
    }

    public fun get_registered_coin_type(self: &ITS, token_id: TokenId): &TypeName {
        assert!(self.registered_coin_types.contains(token_id), EUnregisteredCoin);
        &self.registered_coin_types[token_id]
    }

    public fun get_coin_data<T>(self: &ITS, token_id: TokenId): &CoinData<T> {
        assert!(self.registered_coins.contains(token_id), EUnregisteredCoin);
        &self.registered_coins[token_id]
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

    public fun channel_id(self: &ITS): ID {
        self.channel.id()
    }

    // === Friend-only ===
    public(package) fun channel(self: &ITS): &Channel {
        &self.channel
    }

    public(package) fun channel_mut(self: &mut ITS): &mut Channel {
        &mut self.channel
    }

    public(package) fun coin_management_mut<T>(self: &mut ITS, token_id: TokenId): &mut CoinManagement<T> {
        &mut coin_data_mut<T>(self, token_id).coin_management
    }

    public(package) fun coin_data_mut<T>(self: &mut ITS, token_id: TokenId): &mut CoinData<T> {
        &mut self.registered_coins[token_id]
    }

    public(package) fun add_unregistered_coin<T>(
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

    public(package) fun remove_unregistered_coin<T>(
        self: &mut ITS, token_id: UnregisteredTokenId
    ): (TreasuryCap<T>, CoinMetadata<T>) {
        let UnregisteredCoinData<T> {
            treasury_cap,
            coin_metadata
        } = self.unregistered_coin_info.remove(token_id);

        remove_unregistered_coin_type(self, token_id);

        (treasury_cap, coin_metadata)
    }

    public(package) fun add_registered_coin<T>(
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

    #[test_only]
    public fun new(): ITS {
        let ctx = &mut sui::tx_context::dummy();
        ITS {
            id: object::new(ctx),
            channel: axelar_gateway::channel::new(ctx),

            address_tracker: address_tracker::new(
                ctx,
            ),

            registered_coins: bag::new(ctx),
            registered_coin_types: table::new(ctx),

            unregistered_coin_info: bag::new(ctx),
            unregistered_coin_types: table::new(ctx),

            relayer_discovery_id: object::id_from_address(@0x0)
        }
    }

    #[test_only]
    public fun test_add_unregistered_coin_type(self: &mut ITS, token_id: UnregisteredTokenId, type_name: TypeName) {
        self.add_unregistered_coin_type(token_id, type_name);
    }

    #[test_only]
    public fun test_remove_unregistered_coin_type(self: &mut ITS, token_id: UnregisteredTokenId): TypeName {
        self.remove_unregistered_coin_type(token_id)
    }

    #[test_only]
    public fun test_add_registered_coin_type(self: &mut ITS, token_id: TokenId, type_name: TypeName) {
        self.add_registered_coin_type(token_id, type_name);
    }

    #[test_only]
    public fun test_remove_registered_coin_type(self: &mut ITS, token_id: TokenId): TypeName {
        self.remove_registered_coin_type(token_id)
    }
}
