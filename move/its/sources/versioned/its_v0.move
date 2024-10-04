module its::its_v0;

use axelar_gateway::channel::Channel;
use its::address_tracker::InterchainAddressTracker;
use its::coin_info::CoinInfo;
use its::coin_management::CoinManagement;
use its::token_id::{TokenId, UnregisteredTokenId};
use its::trusted_addresses::TrustedAddresses;
use relayer_discovery::discovery::RelayerDiscovery;
use std::ascii::{Self, String};
use std::type_name::{Self, TypeName};
use sui::bag::Bag;
use sui::coin::{TreasuryCap, CoinMetadata};
use sui::table::Table;
use version_control::version_control::VersionControl;

/// ------
/// Structs
/// ------
public struct ITSV0 has store {
    channel: Channel,
    address_tracker: InterchainAddressTracker,
    unregistered_coin_types: Table<UnregisteredTokenId, TypeName>,
    unregistered_coin_info: Bag,
    registered_coin_types: Table<TokenId, TypeName>,
    registered_coins: Bag,
    relayer_discovery_id: ID,
    version_control: VersionControl,
}

public struct CoinData<phantom T> has store {
    coin_management: CoinManagement<T>,
    coin_info: CoinInfo<T>,
}

public struct UnregisteredCoinData<phantom T> has store {
    treasury_cap: TreasuryCap<T>,
    coin_metadata: CoinMetadata<T>,
}

// ------
// Errors
// ------
/// Trying to find a coin that doesn't exist.
const EUnregisteredCoin: u64 = 0;

/// ------
/// Package Functions
/// ------
public(package) fun new(
    channel: Channel,
    address_tracker: InterchainAddressTracker,
    unregistered_coin_types: Table<UnregisteredTokenId, TypeName>,
    unregistered_coin_info: Bag,
    registered_coin_types: Table<TokenId, TypeName>,
    registered_coins: Bag,
    relayer_discovery_id: ID,
    version_control: VersionControl,
): ITSV0 {
    ITSV0 {
        channel,
        address_tracker,
        unregistered_coin_types,
        unregistered_coin_info,
        registered_coin_types,
        registered_coins,
        relayer_discovery_id,
        version_control,
    }
}

public(package) fun set_relayer_discovery_id(
    self: &mut ITSV0,
    relayer_discovery: &RelayerDiscovery,
) {
    self.relayer_discovery_id = object::id(relayer_discovery);
}

public(package) fun relayer_discovery_id(self: &ITSV0): ID {
    self.relayer_discovery_id
}

public(package) fun set_trusted_address(
    self: &mut ITSV0,
    chain_name: String,
    trusted_address: String,
) {
    self.address_tracker.set_trusted_address(chain_name, trusted_address);
}

public(package) fun set_trusted_addresses(
    self: &mut ITSV0,
    trusted_addresses: TrustedAddresses,
) {
    let (mut chain_names, mut trusted_addresses) = trusted_addresses.destroy();
    let length = chain_names.length();
    let mut i = 0;
    while (i < length) {
        self.set_trusted_address(
            ascii::string(chain_names.pop_back()),
            ascii::string(trusted_addresses.pop_back()),
        );
        i = i + 1;
    }
}

public(package) fun get_trusted_address(
    self: &ITSV0,
    chain_name: String,
): &String {
    self.address_tracker.get_trusted_address(chain_name)
}

public(package) fun is_trusted_address(
    self: &ITSV0,
    source_chain: String,
    source_address: String,
): bool {
    self.address_tracker.is_trusted_address(source_chain, source_address)
}

public(package) fun channel_id(self: &ITSV0): ID {
    self.channel.id()
}

public(package) fun channel_address(self: &ITSV0): address {
    self.channel.to_address()
}

public(package) fun get_coin_data_mut<T>(
    self: &mut ITSV0,
    token_id: TokenId,
): &mut CoinData<T> {
    assert!(self.registered_coins.contains(token_id), EUnregisteredCoin);
    &mut self.registered_coins[token_id]
}

public(package) fun get_coin_data<T>(
    self: &ITSV0,
    token_id: TokenId,
): &CoinData<T> {
    assert!(self.registered_coins.contains(token_id), EUnregisteredCoin);
    &self.registered_coins[token_id]
}

public(package) fun get_coin_info<T>(
    self: &ITSV0,
    token_id: TokenId,
): &CoinInfo<T> {
    &get_coin_data<T>(self, token_id).coin_info
}

public(package) fun channel(self: &ITSV0): &Channel {
    &self.channel
}

public(package) fun channel_mut(self: &mut ITSV0): &mut Channel {
    &mut self.channel
}

public(package) fun version_control(self: &ITSV0): &VersionControl {
    &self.version_control
}

public(package) fun version_control_mut(self: &mut ITSV0): &mut VersionControl {
    &mut self.version_control
}

public(package) fun coin_management_mut<T>(
    self: &mut ITSV0,
    token_id: TokenId,
): &mut CoinManagement<T> {
    let coin_data: &mut CoinData<T> = &mut self.registered_coins[token_id];
    &mut coin_data.coin_management
}

public(package) fun add_unregistered_coin<T>(
    self: &mut ITSV0,
    token_id: UnregisteredTokenId,
    treasury_cap: TreasuryCap<T>,
    coin_metadata: CoinMetadata<T>,
) {
    self
        .unregistered_coin_info
        .add(
            token_id,
            UnregisteredCoinData<T> {
                treasury_cap,
                coin_metadata,
            },
        );

    let type_name = type_name::get<T>();
    add_unregistered_coin_type(self, token_id, type_name);
}

public(package) fun remove_unregistered_coin<T>(
    self: &mut ITSV0,
    token_id: UnregisteredTokenId,
): (TreasuryCap<T>, CoinMetadata<T>) {
    let UnregisteredCoinData<T> {
        treasury_cap,
        coin_metadata,
    } = self.unregistered_coin_info.remove(token_id);

    remove_unregistered_coin_type(self, token_id);

    (treasury_cap, coin_metadata)
}

public(package) fun add_registered_coin<T>(
    self: &mut ITSV0,
    token_id: TokenId,
    mut coin_management: CoinManagement<T>,
    coin_info: CoinInfo<T>,
) {
    coin_management.set_scaling(coin_info.scaling());
    self
        .registered_coins
        .add(
            token_id,
            CoinData<T> {
                coin_management,
                coin_info,
            },
        );

    let type_name = type_name::get<T>();
    add_registered_coin_type(self, token_id, type_name);
}

public(package) fun get_registered_coin_type(
    self: &ITSV0,
    token_id: TokenId,
): &TypeName {
    assert!(self.registered_coin_types.contains(token_id), EUnregisteredCoin);
    &self.registered_coin_types[token_id]
}

public(package) fun get_unregistered_coin_type(
    self: &ITSV0,
    token_id: UnregisteredTokenId,
): &TypeName {
    assert!(self.unregistered_coin_types.contains(token_id), EUnregisteredCoin);

    &self.unregistered_coin_types[token_id]
}

public(package) fun add_unregistered_coin_type(
    self: &mut ITSV0,
    token_id: UnregisteredTokenId,
    type_name: TypeName,
) {
    self.unregistered_coin_types.add(token_id, type_name);
}

public(package) fun remove_unregistered_coin_type(
    self: &mut ITSV0,
    token_id: UnregisteredTokenId,
): TypeName {
    self.unregistered_coin_types.remove(token_id)
}

public(package) fun add_registered_coin_type(
    self: &mut ITSV0,
    token_id: TokenId,
    type_name: TypeName,
) {
    self.registered_coin_types.add(token_id, type_name);
}


/// ------
/// Private Functions
/// ------

#[allow(unused_function)]
fun remove_registered_coin_type_for_testing(
    self: &mut ITSV0,
    token_id: TokenId,
): TypeName {
    self.registered_coin_types.remove(token_id)
}

#[test_only]
public fun test_remove_registered_coin_type_for_testing(
    self: &mut ITSV0,
    token_id: TokenId,
): TypeName {
    self.remove_registered_coin_type_for_testing(token_id)
}
