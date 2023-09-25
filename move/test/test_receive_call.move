module test::test_receive_call {
    use sui::object::{Self, UID};
    use sui::transfer;
    use axelar::channel::{Self, Channel, ApprovedCall};
    use sui::tx_context::{TxContext};
    use sui::event;
  
    struct Empty has store {
  
    }
  
    struct Singleton has key {
        id: UID,
        channel: Channel<Empty>,
    }

    struct Executed has copy, drop {
        data: vector<u8>,
    }

    struct ReceiveCallData has copy, drop {
        singleton_id: address,
    }
  
    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);
        let singleton_id = object::uid_to_address(&id);
        event::emit( ReceiveCallData {
            singleton_id,
        });
        transfer::share_object(Singleton {
            id,
            channel: channel::create_channel<Empty>(Empty {}, ctx),
        });
    }

    public fun execute(singleton: &mut Singleton, call: ApprovedCall) {
        let (
            _,
            _,
            _,
            payload,
        ) = channel::consume_approved_call<Empty>(
            &mut singleton.channel,
            call,
        );
        sui::event::emit(Executed { data: payload });
    }
  }