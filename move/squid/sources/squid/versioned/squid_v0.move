module squid::squid_v0 {
    use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
    use interchain_token_service::interchain_token_service::InterchainTokenService;
    use squid::{coin_bag::{Self, CoinBag}, swap_info::{Self, SwapInfo}};
    use std::ascii::String;
    use sui::{clock::Clock, coin::{Self, Coin}};
    use token::deep::DEEP;
    use version_control::version_control::VersionControl;

    // -----
    // Types
    // -----
    public struct Squid_v0 has store {
        channel: Channel,
        coin_bag: CoinBag,
        version_control: VersionControl,
    }

    // -----------------
    // Package Functions
    // -----------------
    public(package) fun new(version_control: VersionControl, ctx: &mut TxContext): Squid_v0 {
        Squid_v0 {
            channel: channel::new(ctx),
            coin_bag: coin_bag::new(ctx),
            version_control,
        }
    }

    public(package) fun channel(self: &Squid_v0): &Channel {
        &self.channel
    }

    public(package) fun version_control(self: &Squid_v0): &VersionControl {
        &self.version_control
    }

    public(package) fun coin_bag_mut(self: &mut Squid_v0): &mut CoinBag {
        &mut self.coin_bag
    }

    public(package) fun start_swap<T>(
        self: &Squid_v0,
        its: &mut InterchainTokenService,
        approved_message: ApprovedMessage,
        clock: &Clock,
        ctx: &mut TxContext,
    ): SwapInfo {
        let (_, _, data, coin) = its.receive_interchain_transfer_with_data<T>(
            approved_message,
            self.channel(),
            clock,
            ctx,
        );
        let mut swap_info = swap_info::new(data, ctx);
        swap_info.coin_bag().store_estimate<T>(coin.value());
        swap_info.coin_bag().store_balance(coin.into_balance());
        swap_info
    }

    public(package) fun give_deep(self: &mut Squid_v0, deep: Coin<DEEP>) {
        self.coin_bag.store_balance(deep.into_balance());
    }

    public(package) fun allow_function(self: &mut Squid_v0, version: u64, function_name: String) {
        self.version_control.allow_function(version, function_name);
    }

    public(package) fun disallow_function(self: &mut Squid_v0, version: u64, function_name: String) {
        self.version_control.disallow_function(version, function_name);
    }

    #[allow(lint(self_transfer))]
    public(package) fun withdraw<T>(self: &mut Squid_v0, amount: u64, ctx: &mut TxContext) {
        let balance = self.coin_bag.exact_balance<T>(amount);
        transfer::public_transfer(coin::from_balance(balance, ctx), ctx.sender());
    }

    /// ---------
    /// Test Only
    /// ---------
    /// // === HUB CONSTANTS ===
    // Axelar.
    #[test_only]
    const ITS_HUB_CHAIN_NAME: vector<u8> = b"axelar";
    // The address of the ITS HUB.
    #[test_only]
    const ITS_HUB_ADDRESS: vector<u8> = b"hub_address";

    #[test_only]
    public fun new_for_testing(ctx: &mut TxContext): Squid_v0 {
        Squid_v0 {
            channel: channel::new(ctx),
            coin_bag: coin_bag::new(ctx),
            version_control: version_control::version_control::new(vector[]),
        }
    }

    #[test_only]
    use interchain_token_service::coin::COIN;
    #[test_only]
    use sui::test_utils::destroy;

    #[test]
    fun test_start_swap() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = interchain_token_service::interchain_token_service::create_for_testing(ctx);
        let squid = new_for_testing(ctx);
        let token_name = std::string::utf8(b"Name");
        let token_symbol = std::ascii::string(b"Symbol");
        let token_decimals = 10u8;

        let amount = 1234;
        let data = std::bcs::to_bytes(&vector<vector<u8>>[]);
        let coin_management = interchain_token_service::coin_management::new_locked<COIN>();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);

        let token_id = its.register_coin_from_info(token_name, token_symbol, token_decimals, coin_management);

        // This gives some coin to the service.
        let interchain_transfer_ticket = interchain_token_service::interchain_token_service::prepare_interchain_transfer(
            token_id,
            coin,
            std::ascii::string(b"Chain Name"),
            b"Destination Address",
            b"",
            &squid.channel,
        );
        destroy(its.send_interchain_transfer(
            interchain_transfer_ticket,
            &clock,
        ));

        let source_chain = std::ascii::string(b"Chain Name");
        let message_id = std::ascii::string(b"Message Id");
        let its_source_address = b"Source Address";

        let destination_address = squid.channel().to_address();

        let mut writer = abi::abi::new_writer(6);
        writer
            .write_u256(0)
            .write_u256(token_id.to_u256())
            .write_bytes(its_source_address)
            .write_bytes(destination_address.to_bytes())
            .write_u256((amount as u256))
            .write_bytes(data);
        let mut payload = writer.into_bytes();
        payload = interchain_token_service::interchain_token_service_v0::wrap_payload_receiving(payload, source_chain);

        let approved_message = channel::new_approved_message(
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            message_id,
            ITS_HUB_ADDRESS.to_ascii_string(),
            its.channel_address(),
            payload,
        );

        let swap_info = start_swap<COIN>(
            &squid,
            &mut its,
            approved_message,
            &clock,
            ctx,
        );

        destroy(its);
        destroy(squid);
        destroy(swap_info);
        clock.destroy_for_testing();
    }

    #[test]
    fun test_new() {
        let ctx = &mut tx_context::dummy();
        let self = new(version_control::version_control::new(vector[]), ctx);
        destroy(self);
    }
}
