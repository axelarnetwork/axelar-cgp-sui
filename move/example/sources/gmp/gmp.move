module example::gmp;

use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
use axelar_gateway::discovery::{Self, RelayerDiscovery};
use axelar_gateway::gateway;
use gas_service::gas_service::{Self, GasService};
use std::ascii::{Self, String};
use std::type_name;
use sui::address;
use sui::coin::Coin;
use sui::event;
use sui::hex;
use sui::sui::SUI;

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
    let transaction = discovery::new_transaction(
        true,
        vector[
            discovery::new_move_call(
                discovery::new_function(
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
    discovery::register_transaction(discovery, &singleton.channel, transaction);
}

public fun send_call(
    singleton: &Singleton,
    gas_service: &mut GasService,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    refund_address: address,
    coin: Coin<SUI>,
    params: vector<u8>,
) {
    gas_service::pay_gas(
        gas_service,
        coin,
        sui::object::id_address(&singleton.channel),
        destination_chain,
        destination_address,
        payload,
        refund_address,
        params,
    );
    gateway::call_contract(
        &singleton.channel,
        destination_chain,
        destination_address,
        payload,
    );
}

public fun execute(call: ApprovedMessage, singleton: &mut Singleton) {
    let (_, _, _, payload) = singleton.channel.consume_approved_message(call);

    event::emit(Executed { data: payload });
}
