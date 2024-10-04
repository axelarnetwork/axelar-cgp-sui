module example::its_demo;

use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
use axelar_gateway::gateway::{Self, Gateway};
use axelar_gateway::message_ticket::MessageTicket;
use example::utils::concat;
use gas_service::gas_service::GasService;
use its::coin_info;
use its::coin_management;
use its::its::{ITS};
use its::service;
use its::token_id::TokenId;
use relayer_discovery::discovery::RelayerDiscovery;
use relayer_discovery::transaction;
use std::ascii::{Self, String};
use std::type_name;
use sui::address;
use sui::clock::Clock;
use sui::coin::{Self, Coin, CoinMetadata, TreasuryCap};
use sui::event;
use sui::hex;
use sui::sui::SUI;

// -------
// Structs
// -------
public struct Singleton has key {
    id: UID,
    channel: Channel,
    coin_metadata: CoinMetadata<ITS_DEMO>,
    treasury_cap: TreasuryCap<ITS_DEMO>,
}

public struct ExecutedWithToken has copy, drop {
    source_chain: String,
    source_address: vector<u8>,
    data: vector<u8>,
    amount: u64,
}

// ------------
// Capabilities
// ------------
public struct ITS_DEMO has drop {}

// -----
// Setup
// -----
fun init(witness: ITS_DEMO, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        9,
        b"ITS",
        b"ITS Example Coin",
        b"",
        option::none(),
        ctx,
    );
    let singletonId = object::new(ctx);
    let channel = channel::new(ctx);
    transfer::share_object(Singleton {
        id: singletonId,
        channel,
        coin_metadata,
        treasury_cap,
    });
}

// -----
// Public Functions
// -----

/// This needs to be called to register the transaction so that the relayer
/// knows to call this to fulfill calls.
public fun register_transaction(
    discovery: &mut RelayerDiscovery,
    singleton: &Singleton,
    its: &ITS,
    clock: &Clock,
) {
    let arguments = vector[
        vector[2u8],
        concat(vector[0u8], object::id_address(singleton).to_bytes()),
        concat(vector[0u8], object::id_address(its).to_bytes()),
        concat(vector[0u8], object::id_address(clock).to_bytes()),
    ];

    let transaction = transaction::new_transaction(
        true,
        vector[
            transaction::new_move_call(
                transaction::new_function(
                    address::from_bytes(
                        hex::decode(
                            *ascii::as_bytes(
                                &type_name::get_address(
                                    &type_name::get<Singleton>(),
                                ),
                            ),
                        ),
                    ),
                    ascii::string(b"its_example"),
                    ascii::string(b"receive_interchain_transfer"),
                ),
                arguments,
                vector[],
            ),
        ],
    );
    discovery.register_transaction(&singleton.channel, transaction);
}

/// This function needs to be called first to register the coin for either of
/// the other two functions to work.
public fun register_coin(singleton: &Singleton, its: &mut ITS) {
    let coin_info = coin_info::from_info<ITS>(
        singleton.coin_metadata.get_name(),
        singleton.coin_metadata.get_symbol(),
        singleton.coin_metadata.get_decimals(),
        singleton.coin_metadata.get_decimals(),
    );
    let coin_management = coin_management::new_locked();
    service::register_coin(
        its,
        coin_info,
        coin_management,
    );
}

public fun deploy_remote_interchain_token(
    its: &mut ITS,
    gateway: &mut Gateway,
    gas_service: &mut GasService,
    destination_chain: String,
    token_id: TokenId,
    gas: Coin<SUI>,
    gas_params: vector<u8>,
    refund_address: address,
) {
    let message_ticket = service::deploy_remote_interchain_token<ITS_DEMO>(
        its,
        token_id,
        destination_chain,
    );

    pay_gas_and_send_message(
        gateway,
        gas_service,
        gas,
        message_ticket,
        refund_address,
        gas_params,
    );
}

/// This should trigger an interchain trasnfer.
public fun send_interchain_transfer_call(
    singleton: &Singleton,
    its: &mut ITS,
    gateway: &mut Gateway,
    gas_service: &mut GasService,
    token_id: TokenId,
    coin: Coin<ITS_DEMO>,
    destination_chain: String,
    destination_address: vector<u8>,
    metadata: vector<u8>,
    refund_address: address,
    gas: Coin<SUI>,
    gas_params: vector<u8>,
    clock: &Clock,
) {
    let interchain_transfer_ticket = service::prepare_interchain_transfer<ITS_DEMO>(
        token_id,
        coin,
        destination_chain,
        destination_address,
        metadata,
        &singleton.channel,
    );

    let message_ticket = service::send_interchain_transfer<ITS_DEMO>(
        its,
        interchain_transfer_ticket,
        clock,
    );

    pay_gas_and_send_message(
        gateway,
        gas_service,
        gas,
        message_ticket,
        refund_address,
        gas_params,
    );
}

/// This should receive some coins, give them to the executor, and emit and
/// event with all the relevant info.
#[allow(lint(self_transfer))]
public fun receive_interchain_transfer(
    approved_message: ApprovedMessage,
    singleton: &Singleton,
    its: &mut ITS,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (
        source_chain,
        source_address,
        data,
        coin,
    ) = service::receive_interchain_transfer_with_data<ITS_DEMO>(
        its,
        approved_message,
        &singleton.channel,
        clock,
        ctx,
    );

    event::emit(ExecutedWithToken {
        source_chain,
        source_address,
        data,
        amount: coin.value(),
    });

    // give the coin to the caller
    transfer::public_transfer(coin, ctx.sender());
}

/// Call this to obtain some coins for testing.
public fun mint(
    singleton: &mut Singleton,
    amount: u64,
    to: address,
    ctx: &mut TxContext,
) {
    singleton.treasury_cap.mint_and_transfer(amount, to, ctx);
}

// -----
// Internal Functions
// -----
fun pay_gas_and_send_message(
    gateway: &Gateway,
    gas_service: &mut GasService,
    gas: Coin<SUI>,
    message_ticket: MessageTicket,
    refund_address: address,
    gas_params: vector<u8>,
) {
    gas_service.pay_gas(
        gas,
        message_ticket.source_id(),
        message_ticket.destination_chain(),
        message_ticket.destination_address(),
        message_ticket.payload(),
        refund_address,
        gas_params,
    );

    gateway::send_message(gateway, message_ticket);
}
