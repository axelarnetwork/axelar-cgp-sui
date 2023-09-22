module test::test_send_call {
    use sui::object::{Self, UID};
    use sui::transfer;
    use axelar::channel::{Self, Channel};
    use axelar::gateway::{Self};
    use sui::tx_context::{TxContext};
    use std::string::{String};
  
    struct Empty has store {
  
    }
  
    struct Singleton has key {
        id: UID,
        channel: Channel<Empty>,
    }

    struct Executed has copy, drop {
        data: vector<u8>,
    }
  
    fun init(ctx: &mut TxContext) {
       transfer::share_object(Singleton {
            id: object::new(ctx),
            channel: channel::create_channel<Empty>(Empty {}, ctx),
        });
    }

    public fun send_call(singleton: &mut Singleton, destination_chain: String, destination_address: String, payload: vector<u8>) {
        gateway::call_contract(&mut singleton.channel, destination_chain, destination_address, payload);
    }
  }