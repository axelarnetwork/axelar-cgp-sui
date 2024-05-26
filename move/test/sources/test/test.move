module test::test {
    use std::ascii;
    use std::ascii::{String};
    use std::type_name;

    use sui::event;
    use sui::address;
    use sui::hex;

    use axelar::channel::{Self, Channel, ApprovedCall};
    use axelar::discovery::{Self, RelayerDiscovery};

    use axelar::gateway;

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
        let mut arguments = vector::empty<vector<u8>>();
        let mut arg = vector::singleton<u8>(2);
        arguments.push_back(arg);
        arg = vector::singleton<u8>(0);
        vector::append(&mut arg, address::to_bytes(object::id_address(singleton)));
        arguments.push_back(arg);
        let transaction = discovery::new_transaction(
            true,
            vector[
                discovery::new_move_call(
                    discovery::new_function(
                        address::from_bytes(hex::decode(*ascii::as_bytes(&type_name::get_address(&type_name::get<Singleton>())))),
                        ascii::string(b"test"),
                        ascii::string(b"execute")
                    ),
                    arguments,
                    vector[],
                )
            ]
        );
        discovery::register_transaction(discovery, &singleton.channel, transaction);
    }

    public fun send_call(singleton: &Singleton, destination_chain: String, destination_address: String, payload: vector<u8>) {
        gateway::call_contract(&singleton.channel, destination_chain, destination_address, payload);
    }

    public fun execute(call: ApprovedCall, singleton: &mut Singleton) {
        let (
            _,
            _,
            payload,
        ) = channel::consume_approved_call(
            &mut singleton.channel,
            call,
        );
        event::emit(Executed { data: payload });
    }
  }
