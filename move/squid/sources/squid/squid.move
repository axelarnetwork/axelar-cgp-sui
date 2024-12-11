module squid::squid;

use axelar_gateway::channel::ApprovedMessage;
use its::interchain_token_service::InterchainTokenService;
use squid::owner_cap::{Self, OwnerCap};
use squid::squid_v0::{Self, Squid_v0};
use squid::swap_info::SwapInfo;
use std::ascii::{Self, String};
use sui::clock::Clock;
use sui::coin::Coin;
use sui::versioned::{Self, Versioned};
use token::deep::DEEP;
use version_control::version_control::{Self, VersionControl};

// -------
// Version
// -------
const VERSION: u64 = 0;

public struct Squid has key, store {
    id: UID,
    inner: Versioned,
}

fun init(ctx: &mut TxContext) {
    transfer::share_object(Squid {
        id: object::new(ctx),
        inner: versioned::create(
            VERSION,
            squid_v0::new(
                new_version_control(),
                ctx,
            ),
            ctx,
        ),
    });
    transfer::public_transfer(owner_cap::create(ctx), ctx.sender());
}

// ------
// Macros
// ------
/// This macro retrieves the underlying versioned singleton by reference
public(package) macro fun value(
    $self: &Squid,
    $function_name: vector<u8>,
): &Squid_v0 {
    let squid = $self;
    let value = squid.inner().load_value<Squid_v0>();
    value.version_control().check(version(), ascii::string($function_name));
    value
}

/// This macro retrieves the underlying versioned singleton by mutable reference
public(package) macro fun value_mut(
    $self: &mut Squid,
    $function_name: vector<u8>,
): &mut Squid_v0 {
    let squid = $self;
    let value = squid.inner_mut().load_value_mut<Squid_v0>();
    value.version_control().check(version(), ascii::string($function_name));
    value
}

// ---------------
// Entry Functions
// ---------------
entry fun give_deep(self: &mut Squid, deep: Coin<DEEP>) {
    self.value_mut!(b"give_deep").give_deep(deep);
}

entry fun allow_function(
    self: &mut Squid,
    _: &OwnerCap,
    version: u64,
    function_name: String,
) {
    self.value_mut!(b"allow_function").allow_function(version, function_name);
}

entry fun disallow_function(
    self: &mut Squid,
    _: &OwnerCap,
    version: u64,
    function_name: String,
) {
    self
        .value_mut!(b"disallow_function")
        .disallow_function(version, function_name);
}

entry fun withdraw<T>(
    self: &mut Squid,
    _: &OwnerCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    self.value_mut!(b"withdraw").withdraw<T>(amount, ctx);
}

// ----------------
// Public Functions
// ----------------
public fun start_swap<T>(
    self: &mut Squid,
    its: &mut InterchainTokenService,
    approved_message: ApprovedMessage,
    clock: &Clock,
    ctx: &mut TxContext,
): SwapInfo {
    self
        .value_mut!(b"start_swap")
        .start_swap<T>(its, approved_message, clock, ctx)
}

public fun finalize(swap_info: SwapInfo) {
    swap_info.finalize();
}

// -----------------
// Package Functions
// -----------------
public(package) fun inner(self: &Squid): &Versioned {
    &self.inner
}

public(package) fun inner_mut(self: &mut Squid): &mut Versioned {
    &mut self.inner
}

public(package) fun version(): u64 {
    VERSION
}

/// -------
/// Private
/// -------
fun new_version_control(): VersionControl {
    version_control::new(vector[
        // Version 0
        vector[
            b"start_swap",
            b"its_transfer",
            b"deepbook_v3_swap",
            b"register_transaction",
            b"give_deep",
            b"allow_function",
            b"disallow_function",
            b"withdraw",
        ].map!(|function_name| function_name.to_ascii_string()),
    ])
}

#[test_only]
public fun new_for_testing(ctx: &mut TxContext): Squid {
    let mut version_control = new_version_control();
    version_control.allowed_functions()[VERSION].insert(ascii::string(b""));
    Squid {
        id: object::new(ctx),
        inner: versioned::create(
            VERSION,
            squid_v0::new(
                version_control,
                ctx,
            ),
            ctx,
        ),
    }
}

#[test_only]
use its::coin::COIN;

#[test]
fun test_start_swap() {
    let ctx = &mut tx_context::dummy();
    let clock = sui::clock::create_for_testing(ctx);
    let mut its = its::interchain_token_service::create_for_testing(ctx);
    let mut squid = new_for_testing(ctx);

    let coin_info = its::coin_info::from_info<COIN>(
        std::string::utf8(b"Name"),
        std::ascii::string(b"Symbol"),
        10,
    );

    let amount = 1234;
    let data = std::bcs::to_bytes(&vector<vector<u8>>[]);
    let coin_management = its::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);

    let token_id = its.register_coin(
        coin_info,
        coin_management,
    );

    // This gives some coin to InterchainTokenService
    let interchain_transfer_ticket = its::interchain_token_service::prepare_interchain_transfer(
        token_id,
        coin,
        std::ascii::string(b"Chain Name"),
        b"Destination Address",
        b"",
        squid.value!(b"").channel(),
    );
    sui::test_utils::destroy(its.send_interchain_transfer(
        interchain_transfer_ticket,
        &clock,
    ));

    let source_chain = std::ascii::string(b"Chain Name");
    let message_id = std::ascii::string(b"Message Id");
    let message_source_address = std::ascii::string(b"Address");
    let its_source_address = b"Source Address";

    let destination_address = squid.value!(b"").channel().to_address();

    let mut writer = abi::abi::new_writer(6);
    writer
        .write_u256(0)
        .write_u256(token_id.to_u256())
        .write_bytes(its_source_address)
        .write_bytes(destination_address.to_bytes())
        .write_u256((amount as u256))
        .write_bytes(data);
    let payload = writer.into_bytes();

    let approved_message = axelar_gateway::channel::new_approved_message(
        source_chain,
        message_id,
        message_source_address,
        its.channel_address(),
        payload,
    );

    let swap_info = start_swap<COIN>(
        &mut squid,
        &mut its,
        approved_message,
        &clock,
        ctx,
    );

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(squid);
    sui::test_utils::destroy(swap_info);
    clock.destroy_for_testing();
}

#[test]
fun test_init() {
    let ctx = &mut tx_context::dummy();
    init(ctx);
}

#[test]
fun test_allow_function() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new_for_testing(ctx);
    let owner_cap = owner_cap::create(ctx);
    let version = 0;
    let function_name = b"function_name".to_ascii_string();

    self.allow_function(&owner_cap, version, function_name);

    sui::test_utils::destroy(self);
    owner_cap.destroy_for_testing();
}

#[test]
fun test_disallow_function() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new_for_testing(ctx);
    let owner_cap = owner_cap::create(ctx);
    let version = 0;
    let function_name = b"start_swap".to_ascii_string();

    self.disallow_function(&owner_cap, version, function_name);

    sui::test_utils::destroy(self);
    owner_cap.destroy_for_testing();
}

#[test]
fun test_withdraw() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new_for_testing(ctx);
    let owner_cap = owner_cap::create(ctx);
    let amount = 123;

    let balance = sui::balance::create_for_testing<COIN>(amount);
    self.value_mut!(b"").coin_bag_mut().store_balance(balance);
    self.withdraw<COIN>(&owner_cap, amount, ctx);

    sui::test_utils::destroy(self);
    owner_cap.destroy_for_testing();
}
