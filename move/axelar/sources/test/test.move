module test::test {
    use std::ascii;
    use std::vector;
    use std::string::{String};
    use std::type_name;

    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use sui::event;
    use sui::address;

    use axelar::channel::{Self, Channel, ApprovedCall};

    use axelar::gateway;
  
    struct Singleton has key {
        id: UID,
        channel: Channel<ChannelType>,
    }

    struct Executed has copy, drop {
        data: vector<u8>,
    }

    struct ChannelType has key {
        id: UID,
        get_call_info_object_ids: vector<address>,
    }

    struct ChannelWitness has drop {

    }
  
    fun init(ctx: &mut TxContext) {
        let singletonId = object::new(ctx);
        let channel_type = ChannelType { 
            id: object::new(ctx), 
            get_call_info_object_ids: vector::singleton(object::uid_to_address(&singletonId)),
        };
        transfer::share_object(Singleton {
            id: singletonId,
            channel: channel::create_channel<ChannelType, ChannelWitness>(&channel_type, ChannelWitness {}, ctx),
        });
        transfer::share_object(channel_type);
    }

    public fun send_call(singleton: &mut Singleton, destination_chain: String, destination_address: String, payload: vector<u8>) {
        gateway::call_contract(&mut singleton.channel, destination_chain, destination_address, payload);
    }
    public fun get_call_info(_payload: vector<u8>, singleton: &Singleton): ascii::String {
        let v = vector[];
        vector::append(&mut v, b"{\"target\":\"");
        vector::append(&mut v, *ascii::as_bytes(&type_name::get_address(&type_name::get<Singleton>())));
        vector::append(&mut v, b"::test::execute\",\"arguments\":[\"contractCall\",\"obj:");
        vector::append(&mut v, *ascii::as_bytes(&address::to_ascii_string(object::id_address(singleton))));
        vector::append(&mut v, b"\"],\"typeArguments\":[]}");
        ascii::string(v)
    }

    public fun execute(call: ApprovedCall, singleton: &mut Singleton) {
        let (
            _,
            _,
            payload,
        ) = channel::consume_approved_call<ChannelType>(
            &mut singleton.channel,
            call,
        );
        event::emit(Executed { data: payload });
    }
  }