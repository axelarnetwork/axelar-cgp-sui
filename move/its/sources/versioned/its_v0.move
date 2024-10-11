module its::its_v0;

use abi::abi;
use axelar_gateway::channel::{Channel, ApprovedMessage};
use axelar_gateway::gateway;
use axelar_gateway::message_ticket::MessageTicket;
use its::address_tracker::{Self, InterchainAddressTracker};
use its::coin_data::{Self, CoinData};
use its::coin_info::{Self, CoinInfo};
use its::coin_management::{Self, CoinManagement};
use its::events;
use its::interchain_transfer_ticket::InterchainTransferTicket;
use its::token_id::{Self, TokenId, UnregisteredTokenId};
use its::trusted_addresses::TrustedAddresses;
use its::unregistered_coin_data::{Self, UnregisteredCoinData};
use its::utils as its_utils;
use relayer_discovery::discovery::RelayerDiscovery;
use std::ascii::{Self, String};
use std::string;
use std::type_name::{Self, TypeName};
use sui::address;
use sui::bag::{Self, Bag};
use sui::clock::Clock;
use sui::coin::{Self, TreasuryCap, CoinMetadata, Coin};
use sui::table::{Self, Table};
use version_control::version_control::VersionControl;

// ------
// Errors
// ------
#[error]
const EUnregisteredCoin: vector<u8> =
    b"trying to find a coin that doesn't exist";
#[error]
const EUntrustedAddress: vector<u8> =
    b"the sender that sent this message is not trusted";
#[error]
const EInvalidMessageType: vector<u8> =
    b"the message type received is not supported";
#[error]
const EWrongDestination: vector<u8> =
    b"the channel trying to receive this call is not the destination";
#[error]
const EInterchainTransferHasData: vector<u8> =
    b"interchain transfer with data trying to be processed as an interchain transfer";
#[error]
const EInterchainTransferHasNoData: vector<u8> =
    b"interchain transfer trying to be proccessed as an interchain transfer";
#[error]
const EModuleNameDoesNotMatchSymbol: vector<u8> =
    b"the module name does not match the symbol";
#[error]
const ENotDistributor: vector<u8> = b"only the distributor can mint";
#[error]
const ENonZeroTotalSupply: vector<u8> =
    b"trying to give a token that has had some supply already minted";
#[error]
const EUnregisteredCoinHasUrl: vector<u8> =
    b"the interchain token that is being registered has a URL";
#[error]
const EUntrustedChain: vector<u8> = b"the chain is not trusted";
#[error]
const ENewerTicket: vector<u8> = b"cannot proccess newer tickets";

// === MESSAGE TYPES ===
const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
// onst MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;
const MESSAGE_TYPE_SEND_TO_HUB: u256 = 3;
const MESSAGE_TYPE_RECEIVE_FROM_HUB: u256 = 4;

// === HUB CONSTANTS ===
// Chain name for Axelar. This is used for routing ITS calls via ITS hub on
// Axelar.
const ITS_HUB_CHAIN_NAME: vector<u8> = b"axelarnet";
// Identifier to be used as destination address for chains that route to hub.
// For Sui this will probably be every supported chain.
const ITS_HUB_ROUTING_IDENTIFIER: vector<u8> = b"hub";

// === The maximum number of decimals allowed ===
const DECIMALS_CAP: u8 = 9;

// -----
// Types
// -----
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
    let (chain_names, trusted_addresses) = trusted_addresses.destroy();

    chain_names.zip_do!(
        trusted_addresses,
        |chain_name, trusted_address| self.set_trusted_address(
            chain_name,
            trusted_address,
        ),
    );
}

public(package) fun remove_trusted_addresses(
    self: &mut ITS_v0,
    chain_names: vector<String>,
) {
    chain_names.do!(
        |chain_name| self.remove_trusted_address(
            chain_name,
        ),
    );
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

public(package) fun register_coin<T>(
    self: &mut ITS_v0,
    coin_info: CoinInfo<T>,
    coin_management: CoinManagement<T>,
): TokenId {
    let token_id = token_id::from_coin_data(&coin_info, &coin_management);

    self.add_registered_coin(token_id, coin_management, coin_info);

    events::coin_registered<T>(
        token_id,
    );

    token_id
}

public(package) fun deploy_remote_interchain_token<T>(
    self: &ITS_v0,
    token_id: TokenId,
    destination_chain: String,
): MessageTicket {
    let coin_info = self.coin_info<T>(token_id);

    let name = coin_info.name();
    let symbol = coin_info.symbol();
    let decimals = coin_info.decimals();

    let mut writer = abi::new_writer(6);

    writer
        .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
        .write_u256(token_id.to_u256())
        .write_bytes(*name.as_bytes())
        .write_bytes(*symbol.as_bytes())
        .write_u256((decimals as u256))
        .write_bytes(vector::empty());

    events::interchain_token_deployment_started<T>(
        token_id,
        name,
        symbol,
        decimals,
        destination_chain,
    );

    prepare_message(self, destination_chain, writer.into_bytes())
}

public(package) fun send_interchain_transfer<T>(
    self: &mut ITS_v0,
    ticket: InterchainTransferTicket<T>,
    current_version: u64,
    clock: &Clock,
): MessageTicket {
    let (
        token_id,
        balance,
        source_address,
        destination_chain,
        destination_address,
        metadata,
        version,
    ) = ticket.destroy();
    assert!(version <= current_version, ENewerTicket);

    let amount = self
        .coin_management_mut(token_id)
        .take_balance(balance, clock);
    let (_version, data) = its_utils::decode_metadata(metadata);
    let mut writer = abi::new_writer(6);

    writer
        .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
        .write_u256(token_id.to_u256())
        .write_bytes(source_address.to_bytes())
        .write_bytes(destination_address)
        .write_u256(amount)
        .write_bytes(data);

    events::interchain_transfer<T>(
        token_id,
        source_address,
        destination_chain,
        destination_address,
        amount,
        &data,
    );

    self.prepare_message(destination_chain, writer.into_bytes())
}

public(package) fun receive_interchain_transfer<T>(
    self: &mut ITS_v0,
    approved_message: ApprovedMessage,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (source_chain, payload, message_id) = self.decode_approved_message(
        approved_message,
    );
    let mut reader = abi::new_reader(payload);
    assert!(
        reader.read_u256() == MESSAGE_TYPE_INTERCHAIN_TRANSFER,
        EInvalidMessageType,
    );

    let token_id = token_id::from_u256(reader.read_u256());
    let source_address = reader.read_bytes();
    let destination_address = address::from_bytes(reader.read_bytes());
    let amount = reader.read_u256();
    let data = reader.read_bytes();

    assert!(data.is_empty(), EInterchainTransferHasData);

    let coin = self
        .coin_management_mut(token_id)
        .give_coin<T>(amount, clock, ctx);

    transfer::public_transfer(coin, destination_address);

    events::interchain_transfer_received<T>(
        message_id,
        token_id,
        source_chain,
        source_address,
        destination_address,
        amount,
        &b"",
    );
}

public(package) fun receive_interchain_transfer_with_data<T>(
    self: &mut ITS_v0,
    approved_message: ApprovedMessage,
    channel: &Channel,
    clock: &Clock,
    ctx: &mut TxContext,
): (String, vector<u8>, vector<u8>, Coin<T>) {
    let (source_chain, payload, message_id) = self.decode_approved_message(
        approved_message,
    );
    let mut reader = abi::new_reader(payload);
    assert!(
        reader.read_u256() == MESSAGE_TYPE_INTERCHAIN_TRANSFER,
        EInvalidMessageType,
    );

    let token_id = token_id::from_u256(reader.read_u256());

    let source_address = reader.read_bytes();
    let destination_address = address::from_bytes(reader.read_bytes());
    let amount = reader.read_u256();
    let data = reader.read_bytes();

    assert!(destination_address == channel.to_address(), EWrongDestination);
    assert!(!data.is_empty(), EInterchainTransferHasNoData);

    let coin = self.coin_management_mut(token_id).give_coin(amount, clock, ctx);

    events::interchain_transfer_received<T>(
        message_id,
        token_id,
        source_chain,
        source_address,
        destination_address,
        amount,
        &data,
    );

    (source_chain, source_address, data, coin)
}

public(package) fun receive_deploy_interchain_token<T>(
    self: &mut ITS_v0,
    approved_message: ApprovedMessage,
) {
    let (_, payload, _) = self.decode_approved_message(approved_message);
    let mut reader = abi::new_reader(payload);
    assert!(
        reader.read_u256() == MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN,
        EInvalidMessageType,
    );

    let token_id = token_id::from_u256(reader.read_u256());
    let name = string::utf8(reader.read_bytes());
    let symbol = ascii::string(reader.read_bytes());
    let remote_decimals = (reader.read_u256() as u8);
    let distributor_bytes = reader.read_bytes();
    let decimals = if (remote_decimals > DECIMALS_CAP) DECIMALS_CAP
    else remote_decimals;
    let (treasury_cap, mut coin_metadata) = self.remove_unregistered_coin<T>(
        token_id::unregistered_token_id(&symbol, decimals),
    );

    treasury_cap.update_name(&mut coin_metadata, name);

    let mut coin_management = coin_management::new_with_cap<T>(treasury_cap);
    let coin_info = coin_info::from_metadata<T>(coin_metadata, remote_decimals);

    if (distributor_bytes.length() > 0) {
        let distributor = address::from_bytes(distributor_bytes);
        coin_management.add_distributor(distributor);
    };

    self.add_registered_coin<T>(token_id, coin_management, coin_info);
}

public(package) fun give_unregistered_coin<T>(
    self: &mut ITS_v0,
    treasury_cap: TreasuryCap<T>,
    mut coin_metadata: CoinMetadata<T>,
) {
    assert!(treasury_cap.total_supply() == 0, ENonZeroTotalSupply);
    assert!(
        coin::get_icon_url(&coin_metadata).is_none(),
        EUnregisteredCoinHasUrl,
    );

    treasury_cap.update_description(&mut coin_metadata, string::utf8(b""));

    let decimals = coin_metadata.get_decimals();
    let symbol = coin_metadata.get_symbol();

    let module_name = type_name::get_module(&type_name::get<T>());
    assert!(
        &module_name == &its_utils::module_from_symbol(&symbol),
        EModuleNameDoesNotMatchSymbol,
    );

    let token_id = token_id::unregistered_token_id(&symbol, decimals);

    self.add_unregistered_coin<T>(token_id, treasury_cap, coin_metadata);

    events::unregistered_coin_received<T>(
        token_id,
        symbol,
        decimals,
    );
}

public(package) fun mint_as_distributor<T>(
    self: &mut ITS_v0,
    channel: &Channel,
    token_id: TokenId,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    let coin_management = self.coin_management_mut<T>(token_id);
    let distributor = channel.to_address();

    assert!(coin_management.is_distributor(distributor), ENotDistributor);

    coin_management.mint(amount, ctx)
}

public(package) fun mint_to_as_distributor<T>(
    self: &mut ITS_v0,
    channel: &Channel,
    token_id: TokenId,
    to: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    let coin_management = self.coin_management_mut<T>(token_id);
    let distributor = channel.to_address();

    assert!(coin_management.is_distributor(distributor), ENotDistributor);

    let coin = coin_management.mint(amount, ctx);

    transfer::public_transfer(coin, to);
}

public(package) fun burn_as_distributor<T>(
    self: &mut ITS_v0,
    channel: &Channel,
    token_id: TokenId,
    coin: Coin<T>,
) {
    let coin_management = self.coin_management_mut<T>(token_id);
    let distributor = channel.to_address();

    assert!(coin_management.is_distributor<T>(distributor), ENotDistributor);

    coin_management.burn(coin.into_balance());
}

// -----------------
// Private Functions
// -----------------
fun coin_data<T>(self: &ITS_v0, token_id: TokenId): &CoinData<T> {
    assert!(self.registered_coins.contains(token_id), EUnregisteredCoin);
    &self.registered_coins[token_id]
}

fun coin_info<T>(self: &ITS_v0, token_id: TokenId): &CoinInfo<T> {
    coin_data<T>(self, token_id).coin_info()
}

fun is_trusted_address(
    self: &ITS_v0,
    source_chain: String,
    source_address: String,
): bool {
    self.address_tracker.is_trusted_address(source_chain, source_address)
}

fun coin_management_mut<T>(
    self: &mut ITS_v0,
    token_id: TokenId,
): &mut CoinManagement<T> {
    let coin_data: &mut CoinData<T> = &mut self.registered_coins[token_id];
    coin_data.coin_management_mut()
}

fun add_unregistered_coin<T>(
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

fun remove_unregistered_coin<T>(
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

fun trusted_address(self: &ITS_v0, chain_name: String): String {
    *self.address_tracker.trusted_address(chain_name)
}

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

fun add_registered_coin<T>(
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

/// Send a payload to a destination chain. The destination chain needs to have a
/// trusted address.
fun prepare_message(
    self: &ITS_v0,
    mut destination_chain: String,
    mut payload: vector<u8>,
): MessageTicket {
    let mut destination_address = self.trusted_address(destination_chain);

    // Prevent sending directly to the ITS Hub chain. This is not supported yet,
    // so fail early to prevent the user from having their funds stuck.
    assert!(
        destination_chain.into_bytes() != ITS_HUB_CHAIN_NAME,
        EUntrustedChain,
    );

    // Check whether the ITS call should be routed via ITS hub for this
    // destination chain
    if (destination_address.into_bytes() == ITS_HUB_ROUTING_IDENTIFIER) {
        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_SEND_TO_HUB);
        writer.write_bytes(destination_chain.into_bytes());
        writer.write_bytes(payload);
        payload = writer.into_bytes();
        destination_chain = ascii::string(ITS_HUB_CHAIN_NAME);
        destination_address = self.trusted_address(destination_chain);
    };

    gateway::prepare_message(
        &self.channel,
        destination_chain,
        destination_address,
        payload,
    )
}

/// Decode an approved call and check that the source chain is trusted.
fun decode_approved_message(
    self: &ITS_v0,
    approved_message: ApprovedMessage,
): (String, vector<u8>, String) {
    let (mut source_chain, message_id, source_address, mut payload) = self
        .channel
        .consume_approved_message(approved_message);

    assert!(
        self.is_trusted_address(source_chain, source_address),
        EUntrustedAddress,
    );

    let mut reader = abi::new_reader(payload);
    if (reader.read_u256() == MESSAGE_TYPE_RECEIVE_FROM_HUB) {
        assert!(
            source_chain.into_bytes() == ITS_HUB_CHAIN_NAME,
            EUntrustedChain,
        );

        source_chain = ascii::string(reader.read_bytes());
        payload = reader.read_bytes();

        assert!(
            self.trusted_address(source_chain).into_bytes() == ITS_HUB_ROUTING_IDENTIFIER,
            EUntrustedChain,
        );
    } else {
        assert!(
            source_chain.into_bytes() != ITS_HUB_CHAIN_NAME,
            EUntrustedChain,
        );
    };

    (source_chain, payload, message_id)
}
// ---------
// Test Only
// ---------
#[test_only]
use axelar_gateway::channel;
#[test_only]
use its::coin::COIN;

#[test_only]
fun create_for_testing(ctx: &mut TxContext): ITS_v0 {
    let mut self = new(version_control::version_control::new(vector[]), ctx);

    self.set_trusted_address(
        std::ascii::string(b"Chain Name"),
        std::ascii::string(b"Address"),
    );

    self
}

#[test_only]
public fun create_unregistered_coin(
    self: &mut ITS_v0,
    symbol: vector<u8>,
    decimals: u8,
    ctx: &mut TxContext,
) {
    let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(
        symbol,
        decimals,
        ctx,
    );
    let token_id = token_id::unregistered_token_id(
        &ascii::string(symbol),
        decimals,
    );

    self.add_unregistered_coin(token_id, treasury_cap, coin_metadata);
}

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

#[test_only]
public(package) fun trusted_address_for_testing(
    self: &ITS_v0,
    chain_name: String,
): String {
    *self.address_tracker.trusted_address(chain_name)
}

// -----
// Tests
// -----
#[test]
fun test_decode_approved_message_axelar_hub_sender() {
    let ctx = &mut tx_context::dummy();
    let mut self = create_for_testing(ctx);

    let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
    let source_address = ascii::string(b"Address");
    let message_id = ascii::string(b"message_id");
    let origin_chain = ascii::string(b"Source Chain");
    let payload = b"payload";

    let mut writer = abi::new_writer(3);
    writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
    writer.write_bytes(origin_chain.into_bytes());
    writer.write_bytes(payload);
    let payload = writer.into_bytes();

    self.set_trusted_address(source_chain, source_address);
    self.set_trusted_address(
        origin_chain,
        ascii::string(ITS_HUB_ROUTING_IDENTIFIER),
    );

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        source_address,
        self.channel.to_address(),
        payload,
    );

    self.decode_approved_message(approved_message);

    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EUntrustedChain)]
fun test_decode_approved_message_sender_not_hub() {
    let ctx = &mut tx_context::dummy();
    let self = create_for_testing(ctx);

    let source_chain = ascii::string(b"Chain Name");
    let source_address = ascii::string(b"Address");
    let message_id = ascii::string(b"message_id");

    let mut writer = abi::new_writer(3);
    writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
    writer.write_bytes(b"Source Chain");
    writer.write_bytes(b"payload");
    let payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        source_address,
        self.channel.to_address(),
        payload,
    );

    self.decode_approved_message(approved_message);

    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EUntrustedChain)]
fun test_decode_approved_message_origin_not_hub_routed() {
    let ctx = &mut tx_context::dummy();
    let mut self = create_for_testing(ctx);

    let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
    let source_address = ascii::string(b"Address");
    let message_id = ascii::string(b"message_id");
    let origin_chain = ascii::string(b"Source Chain");
    let origin_trusted_address = ascii::string(b"Origin Trusted Address");
    let payload = b"payload";

    let mut writer = abi::new_writer(3);
    writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
    writer.write_bytes(origin_chain.into_bytes());
    writer.write_bytes(payload);
    let payload = writer.into_bytes();

    self.set_trusted_address(source_chain, source_address);
    self.set_trusted_address(origin_chain, origin_trusted_address);

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        source_address,
        self.channel.to_address(),
        payload,
    );

    self.decode_approved_message(approved_message);

    sui::test_utils::destroy(self);
}

#[test]
fun test_prepare_message_to_hub() {
    let ctx = &mut tx_context::dummy();
    let mut self = create_for_testing(ctx);

    let destination_chain = ascii::string(b"Destination Chain");
    let hub_address = ascii::string(b"Address");

    let payload = b"payload";

    self.set_trusted_address(ascii::string(ITS_HUB_CHAIN_NAME), hub_address);
    self.set_trusted_address(
        destination_chain,
        ascii::string(ITS_HUB_ROUTING_IDENTIFIER),
    );

    let message_ticket = self.prepare_message(destination_chain, payload);

    assert!(
        message_ticket.destination_chain() == ascii::string(ITS_HUB_CHAIN_NAME),
    );
    assert!(message_ticket.destination_address() == hub_address);

    sui::test_utils::destroy(self);
    sui::test_utils::destroy(message_ticket);
}

#[test]
#[expected_failure(abort_code = EInvalidMessageType)]
fun test_receive_interchain_transfer_invalid_message_type() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(ctx);

    let coin_info = its::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
        12,
    );

    let amount = 1234;
    let mut coin_management = its::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
    coin_management.take_balance(coin.into_balance(), &clock);

    let token_id = self.register_coin(coin_info, coin_management);
    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let message_source_address = ascii::string(b"Address");
    let its_source_address = b"Source Address";
    let destination_address = @0x1;

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
        .write_u256(token_id.to_u256())
        .write_bytes(its_source_address)
        .write_bytes(destination_address.to_bytes())
        .write_u256((amount as u256))
        .write_bytes(b"");
    let payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        message_source_address,
        self.channel.to_address(),
        payload,
    );

    self.receive_interchain_transfer<COIN>(approved_message, &clock, ctx);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EInterchainTransferHasData)]
fun test_receive_interchain_transfer_passed_data() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(ctx);

    let coin_info = its::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
        12,
    );

    let amount = 1234;
    let mut coin_management = its::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
    coin_management.take_balance(coin.into_balance(), &clock);

    let token_id = self.register_coin(coin_info, coin_management);
    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let message_source_address = ascii::string(b"Address");
    let its_source_address = b"Source Address";
    let destination_address = @0x1;

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
        .write_u256(token_id.to_u256())
        .write_bytes(its_source_address)
        .write_bytes(destination_address.to_bytes())
        .write_u256((amount as u256))
        .write_bytes(b"some data");
    let payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        message_source_address,
        self.channel.to_address(),
        payload,
    );

    self.receive_interchain_transfer<COIN>(approved_message, &clock, ctx);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EInvalidMessageType)]
fun test_receive_interchain_transfer_with_data_invalid_message_type() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(ctx);
    let coin_info = its::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
        12,
    );

    let amount = 1234;
    let mut coin_management = its::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
    coin_management.take_balance(coin.into_balance(), &clock);

    let token_id = self.register_coin(coin_info, coin_management);
    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let message_source_address = ascii::string(b"Address");
    let its_source_address = b"Source Address";
    let channel = channel::new(ctx);
    let destination_address = channel.to_address();

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
        .write_u256(token_id.to_u256())
        .write_bytes(its_source_address)
        .write_bytes(destination_address.to_bytes())
        .write_u256((amount as u256))
        .write_bytes(b"some_data");
    let payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        message_source_address,
        self.channel.to_address(),
        payload,
    );

    let (_, _, _, received_coin) = self.receive_interchain_transfer_with_data<
        COIN,
    >(
        approved_message,
        &channel,
        &clock,
        ctx,
    );

    clock.destroy_for_testing();
    channel.destroy();
    sui::test_utils::destroy(self);
    sui::test_utils::destroy(received_coin);
}

#[test]
#[expected_failure(abort_code = EWrongDestination)]
fun test_receive_interchain_transfer_with_data_wrong_destination() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(ctx);

    let coin_info = its::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
        12,
    );

    let amount = 1234;
    let mut coin_management = its::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
    coin_management.take_balance(coin.into_balance(), &clock);

    let token_id = self.register_coin(coin_info, coin_management);
    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let message_source_address = ascii::string(b"Address");
    let its_source_address = b"Source Address";
    let channel = channel::new(ctx);
    let destination_address = @0x1;

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
        .write_u256(token_id.to_u256())
        .write_bytes(its_source_address)
        .write_bytes(destination_address.to_bytes())
        .write_u256((amount as u256))
        .write_bytes(b"some_data");
    let payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        message_source_address,
        self.channel.to_address(),
        payload,
    );

    let (_, _, _, received_coin) = self.receive_interchain_transfer_with_data<
        COIN,
    >(
        approved_message,
        &channel,
        &clock,
        ctx,
    );

    clock.destroy_for_testing();
    channel.destroy();
    sui::test_utils::destroy(self);
    sui::test_utils::destroy(received_coin);
}

#[test]
#[expected_failure(abort_code = EInterchainTransferHasNoData)]
fun test_receive_interchain_transfer_with_data_no_data() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(ctx);

    let coin_info = its::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
        12,
    );

    let amount = 1234;
    let mut coin_management = its::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
    coin_management.take_balance(coin.into_balance(), &clock);

    let token_id = self.register_coin(coin_info, coin_management);
    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let message_source_address = ascii::string(b"Address");
    let its_source_address = b"Source Address";
    let channel = channel::new(ctx);
    let destination_address = channel.to_address();

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
        .write_u256(token_id.to_u256())
        .write_bytes(its_source_address)
        .write_bytes(destination_address.to_bytes())
        .write_u256((amount as u256))
        .write_bytes(b"");
    let payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        message_source_address,
        self.channel.to_address(),
        payload,
    );

    let (_, _, _, received_coin) = self.receive_interchain_transfer_with_data<
        COIN,
    >(
        approved_message,
        &channel,
        &clock,
        ctx,
    );

    clock.destroy_for_testing();
    channel.destroy();
    sui::test_utils::destroy(self);
    sui::test_utils::destroy(received_coin);
}

#[test]
fun test_receive_deploy_interchain_token_with_distributor() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(ctx);

    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let source_address = ascii::string(b"Address");
    let name = b"Token Name";
    let symbol = b"Symbol";
    let remote_decimals = 8;
    let decimals = if (remote_decimals > DECIMALS_CAP) DECIMALS_CAP
    else remote_decimals;
    let token_id: u256 = 1234;
    let distributor = @0x1;

    self.create_unregistered_coin(symbol, decimals, ctx);

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
        .write_u256(token_id)
        .write_bytes(name)
        .write_bytes(symbol)
        .write_u256((remote_decimals as u256))
        .write_bytes(distributor.to_bytes());
    let payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        source_address,
        self.channel.to_address(),
        payload,
    );

    self.receive_deploy_interchain_token<COIN>(approved_message);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EInvalidMessageType)]
fun test_receive_deploy_interchain_token_invalid_message_type() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(ctx);

    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let source_address = ascii::string(b"Address");
    let name = b"Token Name";
    let symbol = b"Symbol";
    let remote_decimals = 8;
    let decimals = if (remote_decimals > DECIMALS_CAP) DECIMALS_CAP
    else remote_decimals;
    let token_id: u256 = 1234;

    self.create_unregistered_coin(symbol, decimals, ctx);

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
        .write_u256(token_id)
        .write_bytes(name)
        .write_bytes(symbol)
        .write_u256((remote_decimals as u256))
        .write_bytes(b"");
    let payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        source_chain,
        message_id,
        source_address,
        self.channel.to_address(),
        payload,
    );

    self.receive_deploy_interchain_token<COIN>(approved_message);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EUnregisteredCoinHasUrl)]
fun test_give_unregistered_coin_with_url() {
    let name = b"Coin";
    let symbol = b"COIN";
    let decimals = 12;
    let ctx = &mut tx_context::dummy();
    let mut self = create_for_testing(ctx);
    let url = sui::url::new_unsafe_from_bytes(b"url");

    let (
        treasury_cap,
        coin_metadata,
    ) = its::coin::create_treasury_and_metadata_custom(
        name,
        symbol,
        decimals,
        option::some(url),
        ctx,
    );

    self.give_unregistered_coin<COIN>(treasury_cap, coin_metadata);

    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = ENotDistributor)]
fun test_burn_as_distributor_not_distributor() {
    let ctx = &mut tx_context::dummy();
    let mut self = create_for_testing(ctx);
    let symbol = b"COIN";
    let decimals = 9;
    let remote_decimals = 18;
    let amount = 1234;

    let (
        mut treasury_cap,
        coin_metadata,
    ) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
    let coin = treasury_cap.mint(amount, ctx);
    let coin_info = its::coin_info::from_metadata<COIN>(
        coin_metadata,
        remote_decimals,
    );
    let mut coin_management = its::coin_management::new_with_cap(treasury_cap);

    let channel = channel::new(ctx);
    coin_management.add_distributor(@0x1);

    let token_id = self.register_coin(coin_info, coin_management);
    self.burn_as_distributor<COIN>(&channel, token_id, coin);

    sui::test_utils::destroy(self);
    channel.destroy();
}

#[test]
#[expected_failure(abort_code = ENonZeroTotalSupply)]
fun test_give_unregistered_coin_not_zero_total_supply() {
    let symbol = b"COIN";
    let decimals = 12;
    let ctx = &mut tx_context::dummy();
    let mut self = create_for_testing(ctx);

    let (
        mut treasury_cap,
        coin_metadata,
    ) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
    let coin = treasury_cap.mint(1, ctx);

    self.give_unregistered_coin<COIN>(treasury_cap, coin_metadata);

    sui::test_utils::destroy(self);
    sui::test_utils::destroy(coin);
}

#[test]
#[expected_failure(abort_code = EModuleNameDoesNotMatchSymbol)]
fun test_give_unregistered_coin_module_name_missmatch() {
    let symbol = b"SYMBOL";
    let decimals = 12;
    let ctx = &mut tx_context::dummy();
    let mut self = create_for_testing(ctx);

    let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(
        symbol,
        decimals,
        ctx,
    );

    self.give_unregistered_coin<COIN>(treasury_cap, coin_metadata);

    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = ENotDistributor)]
fun test_mint_as_distributor_not_distributor() {
    let ctx = &mut tx_context::dummy();
    let mut self = create_for_testing(ctx);
    let symbol = b"COIN";
    let decimals = 9;
    let remote_decimals = 18;

    let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(
        symbol,
        decimals,
        ctx,
    );
    let coin_info = its::coin_info::from_metadata<COIN>(
        coin_metadata,
        remote_decimals,
    );
    let mut coin_management = its::coin_management::new_with_cap(treasury_cap);

    let channel = channel::new(ctx);
    coin_management.add_distributor(@0x1);
    let amount = 1234;

    let token_id = self.register_coin(coin_info, coin_management);
    let coin = self.mint_as_distributor<COIN>(
        &channel,
        token_id,
        amount,
        ctx,
    );

    assert!(coin.value() == amount);

    sui::test_utils::destroy(self);
    sui::test_utils::destroy(coin);
    channel.destroy();
}
