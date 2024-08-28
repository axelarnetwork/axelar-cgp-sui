module example::its {
    use std::ascii;
    use std::ascii::{String};
    use std::type_name;

    use sui::event;
    use sui::address;
    use sui::hex;
    use sui::coin::{Coin};
    use sui::sui::SUI;
    use sui::clock::Clock;

    use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
    use axelar_gateway::discovery::{Self, RelayerDiscovery, Transaction};

    use gas_service::gas_service::GasService;

    use its::service;
    use its::its::ITS;
    use its::token_id::TokenId;

    public struct Singleton has key {
        id: UID,
        channel: Channel,
    }

    public struct Executed has copy, drop {
        source_chain: String,
        source_address: vector<u8>,
        data: vector<u8>,
        amount: u64,
    }

    fun init(ctx: &mut TxContext) {
        let singletonId = object::new(ctx);
        let channel = channel::new(ctx);
        transfer::share_object(Singleton {
            id: singletonId,
            channel,
        });
    }

    public fun register_transaction(discovery: &mut RelayerDiscovery, singleton: &Singleton, its: &ITS) {
        let mut arguments = vector::empty<vector<u8>>();

        // Singleton object
        let mut arg = vector::singleton<u8>(0);
        arg.append(object::id_address(singleton).to_bytes());
        arguments.push_back(arg);

        // ITS object
        arg = vector::singleton<u8>(0);
        arg.append(object::id_address(its).to_bytes());
        arguments.push_back(arg);

        // payload
        arg = vector[ 3 ];
        arguments.push_back(arg);

        let transaction = discovery::new_transaction(
            true,
            vector[
                discovery::new_move_call(
                    discovery::new_function(
                        address::from_bytes(hex::decode(*ascii::as_bytes(&type_name::get_address(&type_name::get<Singleton>())))),
                        ascii::string(b"its"),
                        ascii::string(b"get_transaction")
                    ),
                    arguments,
                    vector[],
                )
            ]
        );

        discovery::register_transaction(discovery, &singleton.channel, transaction);
    }

    public fun get_transaction(singleton: &Singleton, its: &ITS, payload: vector<u8>): Transaction {
        let mut arguments = vector::empty<vector<u8>>();

        // ApprovedMessage
        let mut arg = vector::singleton<u8>(2);
        arguments.push_back(arg);


        // Singleton object
        arg = vector::singleton<u8>(0);
        arg.append(object::id_address(singleton).to_bytes());
        arguments.push_back(arg);

        // ITS object
        arg = vector::singleton<u8>(0);
        arg.append(object::id_address(its).to_bytes());
        arguments.push_back(arg);
        
        // ITS object
        arg = vector::singleton<u8>(0);
        arg.append(@0x6.to_bytes());
        arguments.push_back(arg);

        let (token_id, _, _, _) = its::discovery::get_interchain_transfer_info(payload);
        let coin_type = its.get_registered_coin_type(token_id);

        discovery::new_transaction(
            true,
            vector[
                discovery::new_move_call(
                    discovery::new_function(
                        address::from_bytes(hex::decode(*ascii::as_bytes(&type_name::get_address(&type_name::get<Singleton>())))),
                        ascii::string(b"its"),
                        ascii::string(b"execute_interchain_transfer")
                    ),
                    arguments,
                    vector[(*coin_type).into_string()],
                )
            ]
        )
    }

    public fun send_interchain_transfer<T>(
        singleton: &Singleton, 
        its: &mut ITS,
        destination_chain: String, 
        destination_address: vector<u8>, 
        token_id: TokenId, 
        coin: Coin<T>,
        metadata: vector<u8>,
        gas_service: &mut GasService, 
        gas: Coin<SUI>, 
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        service::interchain_transfer<T>(
            its,
            token_id,
            coin,
            destination_chain,
            destination_address,
            metadata,
            gas_service, 
            gas,
            &singleton.channel,
            clock,
            ctx,
        );
    }

    public fun execute_interchain_transfer<T>(
        approved_message: ApprovedMessage, 
        singleton: &mut Singleton, 
        its: &mut ITS, 
        clock: &Clock, 
        ctx: &mut TxContext
    ): Coin<T> {
        let (
            source_chain,
            source_address,
            data,
            coin,
        ) = service::receive_interchain_transfer_with_data<T>(
            its,
            approved_message,
            &singleton.channel,
            clock,
            ctx,
        );

        event::emit(Executed { 
            source_chain,
            source_address,
            data,
            amount: coin.value(),
        });

        coin
    }
  }
