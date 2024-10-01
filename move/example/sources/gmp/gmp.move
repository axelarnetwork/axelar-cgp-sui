module example::gmp;

use std::ascii::{Self, String};
use std::type_name;

use sui::address;
use sui::coin::Coin;
use sui::event;
use sui::hex;
use sui::sui::SUI;

use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
use relayer_discovery::discovery::RelayerDiscovery;
use axelar_gateway::gateway::{Self, Gateway};
use relayer_discovery::transaction;

use gas_service::gas_service::GasService;

public struct Singleton has key {
    id: UID,
    channel: Channel,
}

public struct Executed has copy, drop {
    data: vector<u8>,
}

fun init(ctx: &mut TxContext) {
    let singletonId = object::new(ctx);
    let channel = channel::new(ctx);
    transfer::share_object(Singleton {
        id: singletonId,
        channel,
    });
}

public fun register_transaction(
    discovery: &mut RelayerDiscovery,
    singleton: &Singleton,
) {
    let mut arguments = vector::empty<vector<u8>>();
    let mut arg = vector::singleton<u8>(2);
    arguments.push_back(arg);
    arg = vector::singleton<u8>(0);
    arg.append(object::id_address(singleton).to_bytes());
    arguments.push_back(arg);
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
                    ascii::string(b"gmp"),
                    ascii::string(b"execute"),
                ),
                arguments,
                vector[],
            ),
        ],
    );
    discovery.register_transaction(&singleton.channel, transaction);
}

public fun send_call(
    singleton: &Singleton,
    gateway: &Gateway,
    gas_service: &mut GasService,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    refund_address: address,
    coin: Coin<SUI>,
    params: vector<u8>,
) {
    gas_service.pay_gas(
        coin,
        sui::object::id_address(&singleton.channel),
        destination_chain,
        destination_address,
        payload,
        refund_address,
        params,
    );
    let message_ticket = gateway::prepare_message(
        &singleton.channel,
        destination_chain,
        destination_address,
        payload,
    );

    gateway.send_message(message_ticket);
}

public fun execute(call: ApprovedMessage, singleton: &mut Singleton) {
    let (_, _, _, payload) = singleton.channel.consume_approved_message(call);

    event::emit(Executed { data: payload });
}
