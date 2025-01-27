module interchain_token_service::interchain_token_service;

use axelar_gateway::channel::{ApprovedMessage, Channel};
use axelar_gateway::message_ticket::MessageTicket;
use interchain_token_service::coin_info::CoinInfo;
use interchain_token_service::coin_management::CoinManagement;
use interchain_token_service::interchain_token_service_v0::{Self, InterchainTokenService_v0};
use interchain_token_service::interchain_transfer_ticket::{Self, InterchainTransferTicket};
use interchain_token_service::owner_cap::{Self, OwnerCap};
use interchain_token_service::creator_cap::{Self, CreatorCap};
use interchain_token_service::operator_cap::{Self, OperatorCap};
use interchain_token_service::token_id::TokenId;
use relayer_discovery::discovery::RelayerDiscovery;
use relayer_discovery::transaction::Transaction;
use std::ascii::{Self, String};
use std::type_name::TypeName;
use sui::clock::Clock;
use sui::coin::{Coin, TreasuryCap, CoinMetadata};
use sui::versioned::{Self, Versioned};
use version_control::version_control::{Self, VersionControl};

// -------
// Version
// -------
const VERSION: u64 = 0;
const DATA_VERSION: u64 = 0;

// -------
// Structs
// -------
public struct InterchainTokenService has key {
    id: UID,
    inner: Versioned,
}

// -----
// Setup
// -----
fun init(ctx: &mut TxContext) {
    transfer::public_transfer(
        owner_cap::create(ctx),
        ctx.sender(),
    );

    transfer::public_transfer(
        operator_cap::create(ctx),
        ctx.sender(),
    );

    transfer::public_transfer(
        creator_cap::create(ctx),
        ctx.sender(),
    );
}

entry fun setup(creator_cap: CreatorCap, chain_name: String, its_hub_address: String, ctx: &mut TxContext) {
    let inner = versioned::create(
        DATA_VERSION,
        interchain_token_service_v0::new(
            version_control(),
            chain_name,
            its_hub_address,
            ctx,
        ),
        ctx,
    );

    // Share the its object for anyone to use.
    transfer::share_object(InterchainTokenService {
        id: object::new(ctx),
        inner,
    });

    creator_cap.destroy();
}

// ------
// Macros
// ------
/// This macro also uses version control to sinplify things a bit.
macro fun value(
    $self: &InterchainTokenService,
    $function_name: vector<u8>,
): &InterchainTokenService_v0 {
    let its = $self;
    let value = its.inner.load_value<InterchainTokenService_v0>();
    value.version_control().check(VERSION, ascii::string($function_name));
    value
}

/// This macro also uses version control to sinplify things a bit.
macro fun value_mut(
    $self: &mut InterchainTokenService,
    $function_name: vector<u8>,
): &mut InterchainTokenService_v0 {
    let its = $self;
    let value = its.inner.load_value_mut<InterchainTokenService_v0>();
    value.version_control().check(VERSION, ascii::string($function_name));
    value
}

// ---------------
// Entry Functions
// ---------------
entry fun allow_function(
    self: &mut InterchainTokenService,
    _: &OwnerCap,
    version: u64,
    function_name: String,
) {
    self.value_mut!(b"allow_function").allow_function(version, function_name);
}

entry fun disallow_function(
    self: &mut InterchainTokenService,
    _: &OwnerCap,
    version: u64,
    function_name: String,
) {
    self.value_mut!(b"disallow_function").disallow_function(version, function_name);
}

// ----------------
// Public Functions
// ----------------
public fun register_coin<T>(
    self: &mut InterchainTokenService,
    coin_info: CoinInfo<T>,
    coin_management: CoinManagement<T>,
): TokenId {
    let value = self.value_mut!(b"register_coin");

    value.register_coin(coin_info, coin_management)
}

public fun deploy_remote_interchain_token<T>(
    self: &InterchainTokenService,
    token_id: TokenId,
    destination_chain: String,
): MessageTicket {
    let value = self.value!(b"deploy_remote_interchain_token");

    value.deploy_remote_interchain_token<T>(token_id, destination_chain)
}

public fun prepare_interchain_transfer<T>(
    token_id: TokenId,
    coin: Coin<T>,
    destination_chain: String,
    destination_address: vector<u8>,
    metadata: vector<u8>,
    source_channel: &Channel,
): InterchainTransferTicket<T> {
    interchain_transfer_ticket::new<T>(
        token_id,
        coin.into_balance(),
        source_channel.to_address(),
        destination_chain,
        destination_address,
        metadata,
        VERSION,
    )
}

public fun send_interchain_transfer<T>(
    self: &mut InterchainTokenService,
    ticket: InterchainTransferTicket<T>,
    clock: &Clock,
): MessageTicket {
    let value = self.value_mut!(b"send_interchain_transfer");

    value.send_interchain_transfer<T>(
        ticket,
        VERSION,
        clock,
    )
}

public fun receive_interchain_transfer<T>(
    self: &mut InterchainTokenService,
    approved_message: ApprovedMessage,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let value = self.value_mut!(b"receive_interchain_transfer");

    value.receive_interchain_transfer<T>(approved_message, clock, ctx);
}

public fun receive_interchain_transfer_with_data<T>(
    self: &mut InterchainTokenService,
    approved_message: ApprovedMessage,
    channel: &Channel,
    clock: &Clock,
    ctx: &mut TxContext,
): (String, vector<u8>, vector<u8>, Coin<T>) {
    let value = self.value_mut!(b"receive_interchain_transfer_with_data");

    value.receive_interchain_transfer_with_data<T>(
        approved_message,
        channel,
        clock,
        ctx,
    )
}

public fun receive_deploy_interchain_token<T>(
    self: &mut InterchainTokenService,
    approved_message: ApprovedMessage,
) {
    let value = self.value_mut!(b"receive_deploy_interchain_token");

    value.receive_deploy_interchain_token<T>(approved_message);
}

// We need an coin with zero supply that has the proper decimals and typing, and
// no Url.
public fun give_unregistered_coin<T>(
    self: &mut InterchainTokenService,
    treasury_cap: TreasuryCap<T>,
    coin_metadata: CoinMetadata<T>,
) {
    let value = self.value_mut!(b"give_unregistered_coin");

    value.give_unregistered_coin<T>(treasury_cap, coin_metadata);
}

public fun mint_as_distributor<T>(
    self: &mut InterchainTokenService,
    channel: &Channel,
    token_id: TokenId,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    let value = self.value_mut!(b"mint_as_distributor");

    value.mint_as_distributor<T>(
        channel,
        token_id,
        amount,
        ctx,
    )
}

public fun mint_to_as_distributor<T>(
    self: &mut InterchainTokenService,
    channel: &Channel,
    token_id: TokenId,
    to: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    let value = self.value_mut!(b"mint_to_as_distributor");

    value.mint_to_as_distributor<T>(
        channel,
        token_id,
        to,
        amount,
        ctx,
    );
}

public fun burn_as_distributor<T>(
    self: &mut InterchainTokenService,
    channel: &Channel,
    token_id: TokenId,
    coin: Coin<T>,
) {
    let value = self.value_mut!(b"mint_to_as_distributor");

    value.burn_as_distributor<T>(
        channel,
        token_id,
        coin,
    );
}

// This is the entrypoint for operators to set the flow limits of their tokens
// (tokenManager.setFlowLimit on EVM)
public fun set_flow_limit_as_token_operator<T>(
    self: &mut InterchainTokenService,
    channel: &Channel,
    token_id: TokenId,
    limit: u64,
) {
    let value = self.value_mut!(b"set_flow_limit_as_token_operator");

    value.set_flow_limit_as_token_operator<T>(
        channel,
        token_id,
        limit,
    );
}

// This is the entrypoint for operators to set the flow limits of their tokens
// (interchainTokenService.setFlowLimits on EVM)
public fun set_flow_limit<T>(
    self: &mut InterchainTokenService,
    _: &OperatorCap,
    token_ids: TokenId,
    limits: u64,
) {
    let value = self.value_mut!(b"set_flow_limit");

    value.set_flow_limit<T>(
        token_ids,
        limits,
    );
}

// ---------------
// Owner Functions
// ---------------
public fun add_trusted_chains(
    self: &mut InterchainTokenService,
    _owner_cap: &OwnerCap,
    chain_names: vector<String>,
) {
    let value = self.value_mut!(b"add_trusted_chains");

    value.add_trusted_chains(chain_names);
}

public fun remove_trusted_chains(
    self: &mut InterchainTokenService,
    _owner_cap: &OwnerCap,
    chain_names: vector<String>,
) {
    let value = self.value_mut!(b"remove_trusted_chains");

    value.remove_trusted_chains(chain_names);
}

// === Getters ===
public fun registered_coin_type(self: &InterchainTokenService, token_id: TokenId): &TypeName {
    self.package_value().registered_coin_type(token_id)
}

public fun channel_address(self: &InterchainTokenService): address {
    self.package_value().channel_address()
}

// -----------------
// Package Functions
// -----------------
// This function allows the rest of the package to read information about InterchainTokenService
// (discovery needs this).
public(package) fun package_value(self: &InterchainTokenService): &InterchainTokenService_v0 {
    self.inner.load_value<InterchainTokenService_v0>()
}

public(package) fun register_transaction(
    self: &mut InterchainTokenService,
    discovery: &mut RelayerDiscovery,
    transaction: Transaction,
) {
    let value = self.value_mut!(b"register_transaction");

    value.set_relayer_discovery_id(discovery);

    discovery.register_transaction(
        value.channel(),
        transaction,
    );
}

// -----------------
// Private Functions
// -----------------
fun version_control(): VersionControl {
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
            b"add_trusted_chains",
            b"remove_trusted_chains",
            b"register_transaction",
            b"set_flow_limit",
            b"set_flow_limit_as_token_operator",
            b"allow_function",
            b"disallow_function",
        ].map!(|function_name| function_name.to_ascii_string()),
    ])
}

// ---------
// Test Only
// ---------
#[test_only]
use interchain_token_service::coin::COIN;
#[test_only]
use axelar_gateway::channel;
#[test_only]
use std::string;
#[test_only]
use abi::abi;
#[test_only]
use utils::utils;

// === MESSAGE TYPES ===
#[test_only]
const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
#[test_only]
const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
// const MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;
#[test_only]
const MESSAGE_TYPE_RECEIVE_FROM_HUB: u256 = 4;

// === HUB CONSTANTS ===
// Axelar.
#[test_only]
const ITS_HUB_CHAIN_NAME: vector<u8> = b"axelar";
// The address of the ITS HUB.
#[test_only]
const ITS_HUB_ADDRESS: vector<u8> = b"hub_address";

#[test_only]
public fun create_for_testing(ctx: &mut TxContext): InterchainTokenService {
    let mut version_control = version_control();
    version_control.allowed_functions()[0].insert(b"".to_ascii_string());

    let mut value = interchain_token_service_v0::new(
        version_control,
        b"chain name".to_ascii_string(),
        ITS_HUB_ADDRESS.to_ascii_string(),
        ctx,
    );
    value.add_trusted_chain(
        std::ascii::string(b"Chain Name"),
    );

    let inner = versioned::create(
        DATA_VERSION,
        value,
        ctx,
    );

    InterchainTokenService {
        id: object::new(ctx),
        inner,
    }
}

#[test_only]
public(package) fun add_unregistered_coin_type_for_testing(
    self: &mut InterchainTokenService,
    token_id: interchain_token_service::token_id::UnregisteredTokenId,
    type_name: std::type_name::TypeName,
) {
    self.value_mut!(b"").add_unregistered_coin_type_for_testing(token_id, type_name);
}

#[test_only]
public(package) fun remove_unregistered_coin_type_for_testing(
    self: &mut InterchainTokenService,
    token_id: interchain_token_service::token_id::UnregisteredTokenId,
): std::type_name::TypeName {
    self.value_mut!(b"").remove_unregistered_coin_type_for_testing(token_id)
}

#[test_only]
public(package) fun add_registered_coin_type_for_testing(
    self: &mut InterchainTokenService,
    token_id: TokenId,
    type_name: std::type_name::TypeName,
) {
    self.value_mut!(b"").add_registered_coin_type_for_testing(token_id, type_name);
}

#[test_only]
public(package) fun remove_registered_coin_type_for_testing(
    self: &mut InterchainTokenService,
    token_id: TokenId,
): std::type_name::TypeName {
    self.value_mut!(b"").remove_registered_coin_type_for_testing(token_id)
}

// -----
// Tests
// -----
#[test]
fun test_register_coin() {
    let ctx = &mut sui::tx_context::dummy();
    let mut its = create_for_testing(ctx);

    let coin_info = interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );
    let coin_management = interchain_token_service::coin_management::new_locked();

    register_coin(&mut its, coin_info, coin_management);
    utils::assert_event<interchain_token_service::events::CoinRegistered<COIN>>();

    sui::test_utils::destroy(its);
}

#[test]
fun test_deploy_remote_interchain_token() {
    let ctx = &mut sui::tx_context::dummy();
    let mut its = create_for_testing(ctx);
    let token_name = string::utf8(b"Name");
    let token_symbol = ascii::string(b"Symbol");
    let token_decimals = 10;

    let coin_info = interchain_token_service::coin_info::from_info<COIN>(
        token_name,
        token_symbol,
        token_decimals,
    );
    let coin_management = interchain_token_service::coin_management::new_locked();

    let token_id = register_coin(&mut its, coin_info, coin_management);
    let destination_chain = ascii::string(b"Chain Name");
    let message_ticket = deploy_remote_interchain_token<COIN>(
        &its,
        token_id,
        destination_chain,
    );

    utils::assert_event<interchain_token_service::events::InterchainTokenDeploymentStarted<COIN>>();

    let mut writer = abi::new_writer(6);

    writer
        .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
        .write_u256(token_id.to_u256())
        .write_bytes(*token_name.as_bytes())
        .write_bytes(*token_symbol.as_bytes())
        .write_u256((token_decimals as u256))
        .write_bytes(vector::empty());
        
    let payload = interchain_token_service_v0::wrap_payload_sending(writer.into_bytes(), destination_chain);

    assert!(message_ticket.source_id() == its.value!(b"").channel().to_address());
    assert!(message_ticket.destination_chain() == ITS_HUB_CHAIN_NAME.to_ascii_string());
    assert!(message_ticket.destination_address() == ITS_HUB_ADDRESS.to_ascii_string());
    assert!(message_ticket.payload() == payload);
    assert!(message_ticket.version() == 0);

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(message_ticket);
}

#[test]
fun test_deploy_interchain_token() {
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);

    let coin_info = interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );
    let coin_management = interchain_token_service::coin_management::new_locked();

    let token_id = register_coin(&mut its, coin_info, coin_management);

    utils::assert_event<interchain_token_service::events::CoinRegistered<COIN>>();

    let amount = 1234;
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
    let destination_chain = ascii::string(b"Chain Name");
    let destination_address = b"address";
    let metadata = b"";
    let source_channel = channel::new(ctx);
    let clock = sui::clock::create_for_testing(ctx);

    let interchain_transfer_ticket = prepare_interchain_transfer<COIN>(
        token_id,
        coin,
        destination_chain,
        destination_address,
        metadata,
        &source_channel,
    );
    let message_ticket = send_interchain_transfer<COIN>(
        &mut its,
        interchain_transfer_ticket,
        &clock,
    );

    utils::assert_event<interchain_token_service::events::InterchainTransfer<COIN>>();

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
        .write_u256(token_id.to_u256())
        .write_bytes(source_channel.to_address().to_bytes())
        .write_bytes(destination_address)
        .write_u256((amount as u256))
        .write_bytes(b"");
        
    let payload = interchain_token_service_v0::wrap_payload_sending(writer.into_bytes(), destination_chain);

    assert!(message_ticket.source_id() == its.value!(b"").channel().to_address());
    assert!(message_ticket.destination_chain() == ITS_HUB_CHAIN_NAME.to_ascii_string());
    assert!(
        message_ticket.destination_address() == ITS_HUB_ADDRESS.to_ascii_string(),
    );
    assert!(message_ticket.payload() == payload);
    assert!(message_ticket.version() == 0);

    clock.destroy_for_testing();
    source_channel.destroy();
    sui::test_utils::destroy(its);
    sui::test_utils::destroy(message_ticket);
}

#[test]
fun test_receive_interchain_transfer() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut its = create_for_testing(ctx);

    let coin_info = interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );

    let amount = 1234;
    let mut coin_management = interchain_token_service::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
    coin_management.take_balance(coin.into_balance(), &clock);

    let token_id = register_coin(&mut its, coin_info, coin_management);
    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let its_source_address = b"Source Address";
    let destination_address = @0x1;

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
        .write_u256(token_id.to_u256())
        .write_bytes(its_source_address)
        .write_bytes(destination_address.to_bytes())
        .write_u256((amount as u256))
        .write_bytes(b"");
    let mut payload = writer.into_bytes();
    writer = abi::new_writer(3);
    writer
        .write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB)
        .write_bytes(source_chain.into_bytes())
        .write_bytes(payload);
    payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        ITS_HUB_CHAIN_NAME.to_ascii_string(),
        message_id,
        ITS_HUB_ADDRESS.to_ascii_string(),
        its.value!(b"").channel().to_address(),
        payload,
    );

    receive_interchain_transfer<COIN>(&mut its, approved_message, &clock, ctx);

    utils::assert_event<interchain_token_service::events::InterchainTransferReceived<COIN>>();

    clock.destroy_for_testing();
    sui::test_utils::destroy(its);
}

#[test]
fun test_receive_interchain_transfer_with_data() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut its = create_for_testing(ctx);

    let coin_info = interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );

    let amount = 1234;
    let data = b"some_data";
    let mut coin_management = interchain_token_service::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
    coin_management.take_balance(coin.into_balance(), &clock);

    let token_id = its.register_coin(coin_info, coin_management);
    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
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
        .write_bytes(data);
    let mut payload = writer.into_bytes();
    writer = abi::new_writer(3);
    writer
        .write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB)
        .write_bytes(source_chain.into_bytes())
        .write_bytes(payload);
    payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        ITS_HUB_CHAIN_NAME.to_ascii_string(),
        message_id,
        ITS_HUB_ADDRESS.to_ascii_string(),
        its.value!(b"").channel().to_address(),
        payload,
    );

    let (
        received_source_chain,
        received_source_address,
        received_data,
        received_coin,
    ) = its.receive_interchain_transfer_with_data<COIN>(
        approved_message,
        &channel,
        &clock,
        ctx,
    );

    utils::assert_event<interchain_token_service::events::InterchainTransferReceived<COIN>>();

    assert!(received_source_chain == source_chain);
    assert!(received_source_address == its_source_address);
    assert!(received_data == data);
    assert!(received_coin.value() == amount);

    clock.destroy_for_testing();
    channel.destroy();
    sui::test_utils::destroy(its);
    sui::test_utils::destroy(received_coin);
}

#[test]
fun test_receive_deploy_interchain_token() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut its = create_for_testing(ctx);

    let source_chain = ascii::string(b"Chain Name");
    let message_id = ascii::string(b"Message Id");
    let name = b"Token Name";
    let symbol = b"Symbol";
    let decimals = 9;
    let token_id: u256 = 1234;

    its.value_mut!(b"").create_unregistered_coin(symbol, decimals, ctx);

    let mut writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
        .write_u256(token_id)
        .write_bytes(name)
        .write_bytes(symbol)
        .write_u256((decimals as u256))
        .write_bytes(vector::empty());
    let mut payload = writer.into_bytes();
    writer = abi::new_writer(3);
    writer
        .write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB)
        .write_bytes(source_chain.into_bytes())
        .write_bytes(payload);
    payload = writer.into_bytes();

    let approved_message = channel::new_approved_message(
        ITS_HUB_CHAIN_NAME.to_ascii_string(),
        message_id,
        ITS_HUB_ADDRESS.to_ascii_string(),
        its.value!(b"").channel().to_address(),
        payload,
    );

    receive_deploy_interchain_token<COIN>(&mut its, approved_message);

    utils::assert_event<interchain_token_service::events::CoinRegistered<COIN>>();

    clock.destroy_for_testing();
    sui::test_utils::destroy(its);
}

#[test]
fun test_give_unregistered_coin() {
    let symbol = b"COIN";
    let decimals = 12;
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);

    let (
        treasury_cap,
        coin_metadata,
    ) = interchain_token_service::coin::create_treasury_and_metadata(
        symbol,
        decimals,
        ctx,
    );

    give_unregistered_coin<COIN>(&mut its, treasury_cap, coin_metadata);

    sui::test_utils::destroy(its);
}

#[test]
fun test_mint_as_distributor() {
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);
    let symbol = b"COIN";
    let decimals = 9;

    let (
        treasury_cap,
        coin_metadata,
    ) = interchain_token_service::coin::create_treasury_and_metadata(
        symbol,
        decimals,
        ctx,
    );
    let coin_info = interchain_token_service::coin_info::from_metadata<COIN>(
        coin_metadata,
    );
    let mut coin_management = interchain_token_service::coin_management::new_with_cap(treasury_cap);

    let channel = channel::new(ctx);
    coin_management.add_distributor(channel.to_address());
    let amount = 1234;

    let token_id = register_coin(&mut its, coin_info, coin_management);
    let coin = mint_as_distributor<COIN>(
        &mut its,
        &channel,
        token_id,
        amount,
        ctx,
    );

    assert!(coin.value() == amount);

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(coin);
    channel.destroy();
}

#[test]
fun test_mint_to_as_distributor() {
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);
    let symbol = b"COIN";
    let decimals = 9;

    let (
        treasury_cap,
        coin_metadata,
    ) = interchain_token_service::coin::create_treasury_and_metadata(
        symbol,
        decimals,
        ctx,
    );
    let coin_info = interchain_token_service::coin_info::from_metadata<COIN>(
        coin_metadata,
    );
    let mut coin_management = interchain_token_service::coin_management::new_with_cap(treasury_cap);

    let channel = channel::new(ctx);
    coin_management.add_distributor(channel.to_address());
    let amount = 1234;

    let token_id = register_coin(&mut its, coin_info, coin_management);
    mint_to_as_distributor<COIN>(
        &mut its,
        &channel,
        token_id,
        @0x2,
        amount,
        ctx,
    );

    sui::test_utils::destroy(its);
    channel.destroy();
}

#[test]
fun test_burn_as_distributor() {
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);
    let symbol = b"COIN";
    let decimals = 9;
    let amount = 1234;

    let (
        mut treasury_cap,
        coin_metadata,
    ) = interchain_token_service::coin::create_treasury_and_metadata(symbol, decimals, ctx);
    let coin = treasury_cap.mint(amount, ctx);
    let coin_info = interchain_token_service::coin_info::from_metadata<COIN>(
        coin_metadata,
    );
    let mut coin_management = interchain_token_service::coin_management::new_with_cap(treasury_cap);

    let channel = channel::new(ctx);
    coin_management.add_distributor(channel.to_address());

    let token_id = register_coin(&mut its, coin_info, coin_management);
    burn_as_distributor<COIN>(&mut its, &channel, token_id, coin);

    sui::test_utils::destroy(its);
    channel.destroy();
}

#[test]
fun test_add_trusted_chain() {
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);

    let owner_cap = owner_cap::create(
        ctx,
    );

    let trusted_chains = vector[b"Ethereum", b"Avalance", b"Axelar"].map!(
        |chain| chain.to_ascii_string(),
    );

    its.add_trusted_chains(&owner_cap, trusted_chains);
    its.remove_trusted_chains(&owner_cap, trusted_chains);

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(owner_cap);
}

#[test]
fun test_set_flow_limit_as_token_operator() {
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);
    let symbol = b"COIN";
    let decimals = 9;
    let limit = 1234;

    let (
        treasury_cap,
        coin_metadata,
    ) = interchain_token_service::coin::create_treasury_and_metadata(
        symbol,
        decimals,
        ctx,
    );
    let coin_info = interchain_token_service::coin_info::from_metadata<COIN>(
        coin_metadata,
    );
    let mut coin_management = interchain_token_service::coin_management::new_with_cap(treasury_cap);

    let channel = channel::new(ctx);
    coin_management.add_operator(channel.to_address());

    let token_id = register_coin(&mut its, coin_info, coin_management);
    its.set_flow_limit_as_token_operator<COIN>(&channel, token_id, limit);

    sui::test_utils::destroy(its);
    channel.destroy();
}

#[test]
fun test_set_flow_limit() {
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);
    let symbol = b"COIN";
    let decimals = 9;
    let limit = 1234;

    let (
        treasury_cap,
        coin_metadata,
    ) = interchain_token_service::coin::create_treasury_and_metadata(
        symbol,
        decimals,
        ctx,
    );
    let coin_info = interchain_token_service::coin_info::from_metadata<COIN>(
        coin_metadata,
    );
    let coin_management = interchain_token_service::coin_management::new_with_cap(treasury_cap);

    let operator_cap = operator_cap::create(ctx);

    let token_id = register_coin(&mut its, coin_info, coin_management);
    its.set_flow_limit<COIN>(&operator_cap, token_id, limit);

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(operator_cap);
}

#[test]
fun test_init() {
    let mut ts = sui::test_scenario::begin(@0x0);

    init(ts.ctx());
    ts.next_tx(@0x0);

    let owner_cap = ts.take_from_sender<OwnerCap>();
    let operator_cap = ts.take_from_sender<OperatorCap>();
    
    ts.return_to_sender(owner_cap);
    ts.return_to_sender(operator_cap);
    ts.end();
}

#[test]
fun test_setup() {
    let mut ts = sui::test_scenario::begin(@0x0);
    let creator_cap = creator_cap::create(ts.ctx());
    let chain_name = b"chain name".to_ascii_string();

    setup(creator_cap, chain_name, ITS_HUB_ADDRESS.to_ascii_string(), ts.ctx());
    ts.next_tx(@0x0);

    let its = ts.take_shared<InterchainTokenService>();
    let chain_name_hash = axelar_gateway::bytes32::from_bytes(sui::hash::keccak256(&chain_name.into_bytes()));
    assert!(its.value!(b"send_interchain_transfer").chain_name_hash() == chain_name_hash);

    sui::test_scenario::return_shared(its);
    ts.end();
}

#[test]
fun test_registered_coin_type() {
    let ctx = &mut tx_context::dummy();
    let mut its = create_for_testing(ctx);
    let token_id = interchain_token_service::token_id::from_address(@0x1);
    its.add_registered_coin_type_for_testing(
        token_id,
        std::type_name::get<COIN>(),
    );
    its.registered_coin_type(token_id);

    sui::test_utils::destroy(its);
}

#[test]
fun test_channel_address() {
    let ctx = &mut tx_context::dummy();
    let its = create_for_testing(ctx);

    its.channel_address();

    sui::test_utils::destroy(its);
}

#[test]
fun test_allow_function() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = create_for_testing(ctx);
    let owner_cap = owner_cap::create(ctx);
    let version = 0;
    let function_name = b"function_name".to_ascii_string();

    self.allow_function(&owner_cap, version, function_name);

    sui::test_utils::destroy(self);
    sui::test_utils::destroy(owner_cap);
}

#[test]
fun test_disallow_function() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = create_for_testing(ctx);
    let owner_cap = owner_cap::create(ctx);
    let version = 0;
    let function_name = b"send_interchain_transfer".to_ascii_string();

    self.disallow_function(&owner_cap, version, function_name);

    sui::test_utils::destroy(self);
    sui::test_utils::destroy(owner_cap);
}
