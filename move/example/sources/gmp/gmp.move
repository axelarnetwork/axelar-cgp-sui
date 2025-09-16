module example::gmp {
    use axelar_gateway::{channel::{Self, Channel, ApprovedMessage}, gateway::{Self, Gateway}};
    use example::utils::concat;
    use gas_service::gas_service::GasService;
    use relayer_discovery::{discovery::RelayerDiscovery, transaction};
    use std::{ascii::{Self, String}, type_name};
    use sui::{address, coin::Coin, event, hex, sui::SUI};

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

    public fun register_transaction(discovery: &mut RelayerDiscovery, singleton: &Singleton) {
        let arguments = vector[vector[2u8], concat(vector[0u8], object::id_address(singleton).to_bytes())];

        let transaction = transaction::new_transaction(
            true,
            vector[
                transaction::new_move_call(
                    transaction::new_function(
                        address::from_bytes(
                            hex::decode(
                                *ascii::as_bytes(
                                    &type_name::address_string(
                                        &type_name::with_defining_ids<Singleton>(),
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
        let message_ticket = gateway::prepare_message(
            &singleton.channel,
            destination_chain,
            destination_address,
            payload,
        );

        gas_service.pay_gas(
            &message_ticket,
            coin,
            refund_address,
            params,
        );

        gateway.send_message(message_ticket);
    }

    public fun execute(call: ApprovedMessage, singleton: &mut Singleton) {
        let (_, _, _, payload) = singleton.channel.consume_approved_message(call);

        event::emit(Executed { data: payload });
    }
}
