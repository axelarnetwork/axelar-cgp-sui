module squid::squid;

use axelar_gateway::channel::ApprovedMessage;
use its::its::ITS;
use squid::squid_v0::{Self, Squid_v0};
use squid::swap_info::SwapInfo;
use std::ascii;
use sui::clock::Clock;
use sui::versioned::{Self, Versioned};
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

// ----------------
// Public Functions
// ----------------
public fun start_swap<T>(
    self: &mut Squid,
    its: &mut ITS,
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
    let mut its = its::its::create_for_testing(ctx);
    let mut squid = new_for_testing(ctx);

    let coin_info = its::coin_info::from_info<COIN>(
        std::string::utf8(b"Name"),
        std::ascii::string(b"Symbol"),
        10,
        12,
    );

    let amount = 1234;
    let data = std::bcs::to_bytes(&vector<vector<u8>>[]);
    let coin_management = its::coin_management::new_locked();
    let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);

    let token_id = its.register_coin(
        coin_info,
        coin_management,
    );

    // This gives some coin to ITS
    let interchain_transfer_ticket = its::its::prepare_interchain_transfer(
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
