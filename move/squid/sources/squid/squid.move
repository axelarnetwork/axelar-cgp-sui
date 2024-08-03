module squid::squid {
    use sui::clock::Clock;
    
    use axelar_gateway::channel::{Self, Channel, ApprovedMessage};

    use its::service;
    use its::its::ITS;

    use squid::coin_bag::{Self, CoinBag};
    use squid::swap_info::{Self, SwapInfo};

    public struct Squid has key, store{
        id: UID,
        channel: Channel,
        coin_bag: CoinBag,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Squid {
            id: object::new(ctx),
            channel: channel::new(ctx),
            coin_bag: coin_bag::new(ctx),
        });
    }

    public(package) fun borrow_channel(self: &Squid): &Channel {
        &self.channel
    }

    public fun start_swap<T>(self: &mut Squid, its: &mut ITS, approved_message: ApprovedMessage, clock: &Clock, ctx: &mut TxContext): SwapInfo {
        let (_, _, data, coin) = service::receive_interchain_transfer_with_data<T>(
            its,
            approved_message,
            &self.channel,
            clock,
            ctx,
        );
        let mut swap_info = swap_info::new(data, ctx);
        swap_info.coin_bag().store_estimate<T>(
            coin.value(),
        );
        swap_info.coin_bag().store_balance(
            coin.into_balance(),
        );
        swap_info
    }

    public(package) fun coin_bag(self: &mut Squid): &mut CoinBag{
        &mut self.coin_bag
    }

    #[test_only]
    public fun new_for_testing(ctx: &mut TxContext): Squid {
        Squid {
            id: object::new(ctx),
            channel: channel::new(ctx),
            coin_bag: coin_bag::new(ctx),
        }
    }

    #[test_only]
    use its::coin::COIN;

    #[test]
    fun test_start_swap() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();
        let mut squid = new_for_testing(ctx);

        let coin_info = its::coin_info::from_info<COIN>(
            std::string::utf8(b"Name"),
            std::ascii::string(b"Symbol"),
            10,
            12,
        );
        
        let amount = 1234;
        let data = std::bcs::to_bytes(&vector<vector<u8>>[]);
        let coin_management = its::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);

        let token_id = its::service::register_coin(&mut its, coin_info, coin_management);

        // This gives some coin to the service;
        service::interchain_transfer(
            &mut its,
            token_id,
            coin,
            std::ascii::string(b"Chain Name"),
            b"Destination Address",
            b"",
            &clock,
            ctx
        );

        let source_chain = std::ascii::string(b"Chain Name");
        let message_id = std::ascii::string(b"Message Id");
        let message_source_address = std::ascii::string(b"Address");
        let its_source_address = b"Source Address";

        let destination_address = squid.borrow_channel().to_address();
        
        let mut writer = abi::abi::new_writer(6);
        writer
            .write_u256(0)
            .write_u256(token_id.to_u256())
            .write_bytes(its_source_address)
            .write_bytes(destination_address.to_bytes())
            .write_u256((amount as u256))
            .write_bytes(data);
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            message_source_address,
            its.channel_address(),
            payload,
        );

        let swap_info = start_swap<COIN>(&mut squid, &mut its, approved_message, &clock, ctx);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(squid);
        sui::test_utils::destroy(swap_info);
        clock.destroy_for_testing();
    }

    #[test]
    fun test_init() {
        let ctx = &mut tx_context::dummy();
        init(ctx);
    }
}
