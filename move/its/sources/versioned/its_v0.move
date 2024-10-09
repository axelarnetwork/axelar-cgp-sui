module its::its_v0;

use axelar_gateway::channel::Channel;
use its::address_tracker::{Self, InterchainAddressTracker};
use its::coin_data::{Self, CoinData};
use its::coin_info::CoinInfo;
use its::coin_management::CoinManagement;
use its::token_id::{Self, TokenId, UnregisteredTokenId};
use its::trusted_addresses::TrustedAddresses;
use its::unregistered_coin_data::{Self, UnregisteredCoinData};
use relayer_discovery::discovery::RelayerDiscovery;
use std::ascii::String;
use std::string;
use std::type_name::{Self, TypeName};
use sui::bag::{Self, Bag};
use sui::coin::{TreasuryCap, CoinMetadata};
use sui::table::{Self, Table};
use version_control::version_control::VersionControl;

// ------
// Errors
// ------
#[error]
const EUnregisteredCoin: vector<u8> = b"Trying to find a coin that doesn't exist.";

public struct ITS_v0 has store {
    channel: Channel,
    address_tracker: InterchainAddressTracker,
    unregistered_coin_types: Table<UnregisteredTokenId, TypeName>,
    unregistered_coins: Bag,
    registered_coin_types: Table<TokenId, TypeName>,
    registered_coins: Bag,
    relayer_discovery_id: ID,
    version_control: VersionControl,
}

// -----------------
// Package Functions
// -----------------
public(package) fun new(
    version_control: VersionControl,
    ctx: &mut TxContext,
): ITS_v0 {
    ITS_v0 {
        channel: axelar_gateway::channel::new(ctx),
        address_tracker: address_tracker::new(
            ctx,
        ),
        registered_coins: bag::new(ctx),
        registered_coin_types: table::new(ctx),
        unregistered_coins: bag::new(ctx),
        unregistered_coin_types: table::new(ctx),
        relayer_discovery_id: object::id_from_address(@0x0),
        version_control,
    }
}

public(package) fun unregistered_coin_type(
    self: &ITS_v0,
    symbol: &String,
    decimals: u8,
): &TypeName {
    let key = token_id::unregistered_token_id(symbol, decimals);

    assert!(self.unregistered_coin_types.contains(key), EUnregisteredCoin);
    &self.unregistered_coin_types[key]
}

public(package) fun registered_coin_type(
    self: &ITS_v0,
    token_id: TokenId,
): &TypeName {
    assert!(self.registered_coin_types.contains(token_id), EUnregisteredCoin);
    &self.registered_coin_types[token_id]
}

public(package) fun coin_data<T>(
    self: &ITS_v0,
    token_id: TokenId,
): &CoinData<T> {
    assert!(self.registered_coins.contains(token_id), EUnregisteredCoin);
    &self.registered_coins[token_id]
}

public(package) fun coin_info<T>(
    self: &ITS_v0,
    token_id: TokenId,
): &CoinInfo<T> {
    coin_data<T>(self, token_id).coin_info()
}

public(package) fun token_name<T>(
    self: &ITS_v0,
    token_id: TokenId,
): string::String {
    coin_info<T>(self, token_id).name()
}

public(package) fun token_symbol<T>(self: &ITS_v0, token_id: TokenId): String {
    coin_info<T>(self, token_id).symbol()
}

public(package) fun token_decimals<T>(self: &ITS_v0, token_id: TokenId): u8 {
    coin_info<T>(self, token_id).decimals()
}

public(package) fun token_remote_decimals<T>(
    self: &ITS_v0,
    token_id: TokenId,
): u8 {
    coin_info<T>(self, token_id).remote_decimals()
}

public(package) fun trusted_address(self: &ITS_v0, chain_name: String): String {
    *self.address_tracker.trusted_address(chain_name)
}

public(package) fun is_trusted_address(
    self: &ITS_v0,
    source_chain: String,
    source_address: String,
): bool {
    self.address_tracker.is_trusted_address(source_chain, source_address)
}

public(package) fun channel_id(self: &ITS_v0): ID {
    self.channel.id()
}

public(package) fun channel_address(self: &ITS_v0): address {
    self.channel.to_address()
}

public(package) fun set_relayer_discovery_id(
    self: &mut ITS_v0,
    relayer_discovery: &RelayerDiscovery,
) {
    self.relayer_discovery_id = object::id(relayer_discovery);
}

public(package) fun relayer_discovery_id(self: &ITS_v0): ID {
    self.relayer_discovery_id
}

public(package) fun set_trusted_address(
    self: &mut ITS_v0,
    chain_name: String,
    trusted_address: String,
) {
    self.address_tracker.set_trusted_address(chain_name, trusted_address);
}

public(package) fun remove_trusted_address(
    self: &mut ITS_v0,
    chain_name: String,
) { 
    self.address_tracker.remove_trusted_address(chain_name);
}

public(package) fun set_trusted_addresses(
    self: &mut ITS_v0,
    trusted_addresses: TrustedAddresses,
) {
    let (mut chain_names, mut trusted_addresses) = trusted_addresses.destroy();

    let length = chain_names.length();
    let mut i = 0;
    while (i < length) {
        self.set_trusted_address(
            chain_names.pop_back(),
            trusted_addresses.pop_back(),
        );
        i = i + 1;
    }
}

public(package) fun remove_trusted_addresses(
    self: &mut ITS_v0,
    chain_names: vector<String>,
) {
    chain_names.do!(|chain_name| self.remove_trusted_address(
            chain_name,
    ));
}

public(package) fun coin_data_mut<T>(
    self: &mut ITS_v0,
    token_id: TokenId,
): &mut CoinData<T> {
    assert!(self.registered_coins.contains(token_id), EUnregisteredCoin);
    &mut self.registered_coins[token_id]
}

public(package) fun channel(self: &ITS_v0): &Channel {
    &self.channel
}

public(package) fun channel_mut(self: &mut ITS_v0): &mut Channel {
    &mut self.channel
}

public(package) fun version_control(self: &ITS_v0): &VersionControl {
    &self.version_control
}

public(package) fun version_control_mut(
    self: &mut ITS_v0,
): &mut VersionControl {
    &mut self.version_control
}

public(package) fun coin_management_mut<T>(
    self: &mut ITS_v0,
    token_id: TokenId,
): &mut CoinManagement<T> {
    let coin_data: &mut CoinData<T> = &mut self.registered_coins[token_id];
    coin_data.coin_management_mut()
}

public(package) fun add_unregistered_coin<T>(
    self: &mut ITS_v0,
    token_id: UnregisteredTokenId,
    treasury_cap: TreasuryCap<T>,
    coin_metadata: CoinMetadata<T>,
) {
    self
        .unregistered_coins
        .add(
            token_id,
            unregistered_coin_data::new(
                treasury_cap,
                coin_metadata,
            ),
        );

    let type_name = type_name::get<T>();
    add_unregistered_coin_type(self, token_id, type_name);
}

public(package) fun remove_unregistered_coin<T>(
    self: &mut ITS_v0,
    token_id: UnregisteredTokenId,
): (TreasuryCap<T>, CoinMetadata<T>) {
    let unregistered_coins: UnregisteredCoinData<T> = self
        .unregistered_coins
        .remove(token_id);
    let (treasury_cap, coin_metadata) = unregistered_coins.destroy();

    remove_unregistered_coin_type(self, token_id);

    (treasury_cap, coin_metadata)
}

public(package) fun add_registered_coin<T>(
    self: &mut ITS_v0,
    token_id: TokenId,
    mut coin_management: CoinManagement<T>,
    coin_info: CoinInfo<T>,
) {
    coin_management.set_scaling(coin_info.scaling());
    self
        .registered_coins
        .add(
            token_id,
            coin_data::new(
                coin_management,
                coin_info,
            ),
        );

    let type_name = type_name::get<T>();
    add_registered_coin_type(self, token_id, type_name);
}

// -----------------
// Private Functions
// -----------------
fun add_unregistered_coin_type(
    self: &mut ITS_v0,
    token_id: UnregisteredTokenId,
    type_name: TypeName,
) {
    self.unregistered_coin_types.add(token_id, type_name);
}

fun remove_unregistered_coin_type(
    self: &mut ITS_v0,
    token_id: UnregisteredTokenId,
): TypeName {
    self.unregistered_coin_types.remove(token_id)
}

fun add_registered_coin_type(
    self: &mut ITS_v0,
    token_id: TokenId,
    type_name: TypeName,
) {
    self.registered_coin_types.add(token_id, type_name);
}

// ---------
// Test Only
// ---------
#[test_only]
public(package) fun add_unregistered_coin_type_for_testing(
    self: &mut ITS_v0,
    token_id: UnregisteredTokenId,
    type_name: TypeName,
) {
    self.add_unregistered_coin_type(token_id, type_name);
}

#[test_only]
public(package) fun remove_unregistered_coin_type_for_testing(
    self: &mut ITS_v0,
    token_id: UnregisteredTokenId,
): TypeName {
    self.remove_unregistered_coin_type(token_id)
}

#[test_only]
public(package) fun add_registered_coin_type_for_testing(
    self: &mut ITS_v0,
    token_id: TokenId,
    type_name: TypeName,
) {
    self.add_registered_coin_type(token_id, type_name);
}

#[test_only]
public(package) fun remove_registered_coin_type_for_testing(
    self: &mut ITS_v0,
    token_id: TokenId,
): TypeName {
    self.remove_registered_coin_type_for_testing(token_id)
}
