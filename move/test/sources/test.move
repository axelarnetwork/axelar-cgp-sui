module axelar_sui_sample::test {
    use sui::object::{Self, UID};
    use sui::transfer;
    use axelar::channel::{Self, Channel, ApprovedCall};
    use sui::tx_context::{TxContext};
  
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