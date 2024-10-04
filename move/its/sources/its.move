module its::its;

use axelar_gateway::channel::Channel;
use its::address_tracker::{Self};
use its::coin_info::CoinInfo;
use its::coin_management::CoinManagement;
use its::token_id::{Self, TokenId, UnregisteredTokenId};
use its::trusted_addresses::{Self, TrustedAddresses};
use its::its_v0::{Self, ITSV0, CoinData};
use relayer_discovery::discovery::RelayerDiscovery;
use std::ascii::{Self, String};
use std::string;
use std::type_name::{TypeName};
use sui::coin::{TreasuryCap, CoinMetadata};
use sui::table::{Self};
use sui::bag::{Self};
use sui::versioned::{Self, Versioned};
use version_control::version_control::{Self, VersionControl};

// -------
// Version
// -------
const VERSION: u64 = 0;

public struct ITS has key {
    id: UID,
    inner: Versioned,
}

// === Initializer ===
fun init(ctx: &mut TxContext) {
	let inner = versioned::create(
		VERSION,
		its_v0::new(
			axelar_gateway::channel::new(ctx),
			address_tracker::new(
				ctx,
			),
			table::new(ctx),
			bag::new(ctx),
			table::new(ctx),
			bag::new(ctx),
			object::id_from_address(@0x0),
			new_version_control(),
		),
		ctx,
	);

	transfer::share_object(ITS {
		id: object::new(ctx),
		inner,
	});
}


// ------
// Macros
// ------
/// This macro also uses version control to simplify things a bit.
macro fun value($self: &ITS, $function_name: vector<u8>): &ITSV0 {
    let its = $self;
    let value = its.inner.load_value<ITSV0>();
    value.version_control().check(VERSION, ascii::string($function_name));
    value
}

/// This macro also uses version control to simplify things a bit.
macro fun value_mut($self: &mut ITS, $function_name: vector<u8>): &mut ITSV0 {
    let its = $self;
    let value = its.inner.load_value_mut<ITSV0>();
    value.version_control().check(VERSION, ascii::string($function_name));
    value
}

// === Getters ===
public fun get_unregistered_coin_type(
    self: &ITS,
    symbol: &String,
    decimals: u8,
): &TypeName {
    let key = token_id::unregistered_token_id(symbol, decimals);

	let value = self.value!(b"get_unregistered_coin_type");
	value.get_unregistered_coin_type(key)
}

public fun get_registered_coin_type(self: &ITS, token_id: TokenId): &TypeName {
	let value = self.value!(b"get_registered_coin_type");
	value.get_registered_coin_type(token_id)
}

public fun get_coin_data<T>(self: &ITS, token_id: TokenId): &CoinData<T> {
	let value = self.value!(b"get_coin_data");
	value.get_coin_data(token_id)
}

public fun get_coin_info<T>(self: &ITS, token_id: TokenId): &CoinInfo<T> {
	let value = self.value!(b"get_coin_info");
	value.get_coin_info(token_id)
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

public fun token_remote_decimals<T>(self: &ITS, token_id: TokenId): u8 {
    get_coin_info<T>(self, token_id).remote_decimals()
}

public fun get_trusted_address(self: &ITS, chain_name: String): String {
	let value = self.value!(b"get_trusted_address");
	*value.get_trusted_address(chain_name)
}

public fun is_trusted_address(
    self: &ITS,
    source_chain: String,
    source_address: String,
): bool {
	let value = self.value!(b"is_trusted_address");
	value.is_trusted_address(source_chain, source_address)
}

public fun channel_id(self: &ITS): ID {
	let value = self.value!(b"channel_id");
	value.channel_id()
}

public fun channel_address(self: &ITS): address {
	let value = self.value!(b"channel_address");
	value.channel_address()
}

public(package) fun set_relayer_discovery_id(
    self: &mut ITS,
    relayer_discovery: &RelayerDiscovery,
) {
	let value = self.value_mut!(b"set_relayer_discovery_id");
	value.set_relayer_discovery_id(relayer_discovery);
}

public(package) fun relayer_discovery_id(self: &ITS): ID {
	let value = self.value!(b"relayer_discovery_id");
	value.relayer_discovery_id()
}

public(package) fun set_trusted_address(
    self: &mut ITS,
    chain_name: String,
    trusted_address: String,
) {
	let value = self.value_mut!(b"set_trusted_address");
	value.set_trusted_address(chain_name, trusted_address);
}

public(package) fun set_trusted_addresses(
    self: &mut ITS,
    trusted_addresses: TrustedAddresses,
) {
   let value = self.value_mut!(b"set_trusted_addresses");
   value.set_trusted_addresses(trusted_addresses);
}

public(package) fun get_coin_data_mut<T>(
    self: &mut ITS,
    token_id: TokenId,
): &mut CoinData<T> {
	let value = self.value_mut!(b"get_coin_data_mut");
	value.get_coin_data_mut(token_id)
}

public(package) fun channel(self: &ITS): &Channel {
	let value = self.value!(b"channel");
	value.channel()
}

public(package) fun channel_mut(self: &mut ITS): &mut Channel {
	let value = self.value_mut!(b"channel_mut");
	value.channel_mut()
}

public(package) fun version_control(self: &ITS): &VersionControl {
	let value = self.value!(b"version_control");
	value.version_control()
}

public(package) fun version_control_mut(self: &mut ITS): &mut VersionControl {
	let value = self.value_mut!(b"version_control_mut");
	value.version_control_mut()
}

public(package) fun coin_management_mut<T>(
    self: &mut ITS,
    token_id: TokenId,
): &mut CoinManagement<T> {
	let value = self.value_mut!(b"coin_management_mut");
	value.coin_management_mut(token_id)
}

public(package) fun add_unregistered_coin<T>(
    self: &mut ITS,
    token_id: UnregisteredTokenId,
    treasury_cap: TreasuryCap<T>,
    coin_metadata: CoinMetadata<T>,
) {
   let value = self.value_mut!(b"add_unregistered_coin");
   value.add_unregistered_coin(token_id, treasury_cap, coin_metadata);
}

public(package) fun remove_unregistered_coin<T>(
    self: &mut ITS,
    token_id: UnregisteredTokenId,
): (TreasuryCap<T>, CoinMetadata<T>) {
   let value = self.value_mut!(b"remove_unregistered_coin");
   value.remove_unregistered_coin(token_id)
}

public(package) fun add_registered_coin<T>(
    self: &mut ITS,
    token_id: TokenId,
    coin_management: CoinManagement<T>,
    coin_info: CoinInfo<T>,
) {
   let value = self.value_mut!(b"add_registered_coin");
   value.add_registered_coin(token_id, coin_management, coin_info);
}

public(package) fun add_registered_coin_type(
    self: &mut ITS,
    token_id: TokenId,
    type_name: TypeName,
) {
	let value = self.value_mut!(b"add_registered_coin_type");
    value.add_registered_coin_type(token_id, type_name);
}

fun new_version_control(): VersionControl {
    version_control::new(vector[
        // Version 0
        vector[
            b"register_coin",
            b"deploy_remote_interchain_token",
            b"send_interchain_transfer",
            b"receive_interchain_transfer",
            b"receive_interchain_transfer_with_data",
            b"receive_deploy_interchain_token",
            b"give_unregistered_coin",
            b"mint_as_distributor",
            b"mint_to_as_distributor",
            b"burn_as_distributor",
            b"set_trusted_addresses",
			b"channel",
			b"version_control",
			b"channel_mut",
			b"add_registered_coin",
			b"is_trusted_address",
			b"coin_management_mut",
			b"add_unregistered_coin",
            b"add_unregistered_coin_type",
			b"add_registered_coin_type",
			b"get_registered_coin_type",
			b"remove_unregistered_coin_type",
			b"remove_unregistered_coin",
			b"set_trusted_address",
			b"get_trusted_address",
			b"get_coin_info",
			b"set_relayer_discovery_id",
			b"channel_id",
			b"get_unregistered_coin_type",
			b"relayer_discovery_id",
        ].map!(|function_name| function_name.to_ascii_string()),
    ])
}

// === Tests ===
#[test_only]
public fun new_for_testing(): ITS {
    let ctx = &mut sui::tx_context::dummy();
	let mut version_control = new_version_control();

	let inner = versioned::create(
		VERSION,
		its_v0::new(
			axelar_gateway::channel::new(ctx),
			address_tracker::new(
				ctx,
			),
			table::new(ctx),
			bag::new(ctx),
			table::new(ctx),
			bag::new(ctx),
			object::id_from_address(@0x0),
			version_control,
		),
		ctx,
	);

    let mut its = ITS {
        id: object::new(ctx),
		inner
	};

	let trusted_addresses = trusted_addresses::new_for_testing(
		vector[
			b"Chain Name",
		],
		vector[
			b"Address",
		],
	);

    its.set_trusted_addresses(trusted_addresses);

    its
}

#[test_only]
public fun remove_unregistered_coin_type_for_testing(
    self: &mut ITS,
    token_id: UnregisteredTokenId,
): TypeName {
	let value = self.value_mut!(b"remove_unregistered_coin_type");
    value.remove_unregistered_coin_type(token_id)
}

#[test_only]
public fun add_unregistered_coin_type_for_testing(
    self: &mut ITS,
	token_id: UnregisteredTokenId,
	type_name: TypeName,
) {
	let value = self.value_mut!(b"add_unregistered_coin_type");
    value.add_unregistered_coin_type(token_id, type_name);
}

