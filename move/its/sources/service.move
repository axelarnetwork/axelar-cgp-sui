module its::service {
    use std::string;
    use std::ascii::{Self, String};
    use std::type_name;

    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::address;
    use sui::event;
    use sui::bcs;
    use sui::clock::Clock;

    use abi::abi;

    use axelar_gateway::channel::{Self, ApprovedMessage};
    use axelar_gateway::gateway::{Self, MessageTicket};
    use axelar_gateway::channel::Channel;

    use governance::governance::{Self, Governance};

    use its::its::{ITS};
    use its::coin_info::{Self, CoinInfo};
    use its::token_id::{Self, TokenId};
    use its::coin_management::{Self, CoinManagement};
    use its::utils as its_utils;
    use its::trusted_addresses;

    // === VERSION ===
    const VERSION: u64 = 0;

    // === MESSAGE TYPES ===
    const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
    const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
    //const MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;
    const MESSAGE_TYPE_SEND_TO_HUB: u256 = 3;
    const MESSAGE_TYPE_RECEIVE_FROM_HUB: u256 = 4;    
    // address::to_u256(address::from_bytes(keccak256(b"sui-set-trusted-addresses")));
    const MESSAGE_TYPE_SET_TRUSTED_ADDRESSES: u256 = 0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68;

    /// -----
    /// Types
    /// -----
    public struct InterchainTransferTicket<phantom T>{
        token_id: TokenId,
        coin: Coin<T>,
        source_address: address,
        destination_chain: String,
        destination_address: vector<u8>,
        metadata: vector<u8>,
        version: u64,
    }

    // === HUB CONSTANTS ===
    // Chain name for Axelar. This is used for routing ITS calls via ITS hub on Axelar.
    const ITS_HUB_CHAIN_NAME: vector<u8> = b"Axelarnet";
    // Identifier to be used as destination address for chains that route to hub. For Sui this will probably be every supported chain.
    const ITS_HUB_ROUTING_IDENTIFIER: vector<u8> = b"hub";

    // === The maximum number of decimals allowed ===
    const DECIMALS_CAP: u8 = 9;

    // === ERRROS CODES ===
    const EUntrustedAddress: u64 = 0;
    const EInvalidMessageType: u64 = 1;
    const EWrongDestination: u64 = 2;
    const EInterchainTransferHasData: u64 = 3;
    const EInterchainTransferHasNoData: u64 = 4;
    const EModuleNameDoesNotMatchSymbol: u64 = 5;
    const ENotDistributor: u64 = 6;
    const ENonZeroTotalSupply: u64 = 7;
    const EUnregisteredCoinHasUrl: u64 = 8;
    const EUntrustedChain: u64 = 9;
    const ERemainingData: u64 = 10;
    const ENewerTicket: u64 = 11;

    // === Events ===
    public struct CoinRegistered<phantom T> has copy, drop {
        token_id: TokenId,
    }

    // === Public Functions ===
    public fun register_coin<T>(
        self: &mut ITS, coin_info: CoinInfo<T>, coin_management: CoinManagement<T>
    ): TokenId {
        let token_id = token_id::from_coin_data(&coin_info, &coin_management);

        self.add_registered_coin(token_id, coin_management, coin_info);

        event::emit(CoinRegistered<T> {
            token_id
        });

        token_id
    }

    public fun deploy_remote_interchain_token<T>(
        self: &mut ITS, token_id: TokenId, destination_chain: String
    ): MessageTicket {
        let coin_info = self.get_coin_info<T>(token_id);
        let name = coin_info.name();
        let symbol = coin_info.symbol();
        let decimals = coin_info.decimals();
        let mut writer = abi::new_writer(6);

        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id.to_u256())
            .write_bytes(*string::as_bytes(&name))
            .write_bytes(*ascii::as_bytes(&symbol))
            .write_u256((decimals as u256))
            .write_bytes(vector::empty());

        prepare_message(self, destination_chain, writer.into_bytes())
    }

    public fun prepare_interchain_transfer<T>(
        token_id: TokenId,
        coin: Coin<T>,
        destination_chain: String,
        destination_address: vector<u8>,
        metadata: vector<u8>,
        source_channel: &Channel,
    ): InterchainTransferTicket<T> {
        InterchainTransferTicket<T> {
            token_id,
            coin,
            source_address: source_channel.to_address(),
            destination_chain,
            destination_address,
            metadata,
            version: VERSION,
        }
    }

    public fun send_interchain_transfer<T>(
        self: &mut ITS,
        ticket: InterchainTransferTicket<T>,
        clock: &Clock,
    ): MessageTicket {
        let InterchainTransferTicket {
           token_id,
           coin,
           source_address,
           destination_chain,
           destination_address,
           metadata, 
           version,
        } = ticket;
        assert!(version <= VERSION, ENewerTicket);
        let amount = self.coin_management_mut(token_id)
            .take_coin(coin, clock);
        let (_version, data) = its_utils::decode_metadata(metadata);
        let mut writer = abi::new_writer(6);

        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id.to_u256())
            .write_bytes(source_address.to_bytes())
            .write_bytes(destination_address)
            .write_u256(amount)
            .write_bytes(data);

        prepare_message(self, destination_chain, writer.into_bytes())
    }

    public fun receive_interchain_transfer<T>(self: &mut ITS, approved_message: ApprovedMessage, clock: &Clock, ctx: &mut TxContext) {
        let (_, payload) = decode_approved_message(self, approved_message);
        let mut reader = abi::new_reader(payload);
        assert!(reader.read_u256() == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);

        let token_id = token_id::from_u256(reader.read_u256());
        reader.skip_slot(); // skip source_address
        let destination_address = address::from_bytes(reader.read_bytes());
        let amount = reader.read_u256();
        let data = reader.read_bytes();

        assert!(data.is_empty(), EInterchainTransferHasData);

        let coin = self
            .coin_management_mut(token_id)
            .give_coin<T>(amount, clock, ctx);

        transfer::public_transfer(coin, destination_address)
    }

    public fun receive_interchain_transfer_with_data<T>(
        self: &mut ITS,
        approved_message: ApprovedMessage,
        channel: &Channel,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (String, vector<u8>, vector<u8>, Coin<T>) {
        let (source_chain, payload) = decode_approved_message(self, approved_message);
        let mut reader = abi::new_reader(payload);
        assert!(reader.read_u256() == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);

        let token_id = token_id::from_u256(reader.read_u256());

        let source_address = reader.read_bytes();
        let destination_address = reader.read_bytes();
        let amount = reader.read_u256();
        let data = reader.read_bytes();

        assert!(address::from_bytes(destination_address) == channel.to_address(), EWrongDestination);
        assert!(!data.is_empty(), EInterchainTransferHasNoData);

        let coin = self
            .coin_management_mut(token_id)
            .give_coin(amount, clock, ctx);

        (
            source_chain,
            source_address,
            data,
            coin,
        )
    }

    public fun receive_deploy_interchain_token<T>(self: &mut ITS, approved_message: ApprovedMessage) {
        let (_, payload) = decode_approved_message(self, approved_message);
        let mut reader = abi::new_reader(payload);
        assert!(reader.read_u256() == MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, EInvalidMessageType);

        let token_id = token_id::from_u256(reader.read_u256());
        let name = string::utf8(reader.read_bytes());
        let symbol = ascii::string(reader.read_bytes());
        let remote_decimals = (reader.read_u256() as u8);
        let distributor_bytes = reader.read_bytes();
        let decimals = if (remote_decimals > DECIMALS_CAP) DECIMALS_CAP else remote_decimals;
        let (treasury_cap, mut coin_metadata) = self.remove_unregistered_coin<T>(
            token_id::unregistered_token_id(&symbol, decimals)
        );

        treasury_cap.update_name(&mut coin_metadata, name);
        //coin::update_symbol(&treasury_cap, &mut coin_metadata, symbol);

        let mut coin_management = coin_management::new_with_cap<T>(treasury_cap);
        let coin_info = coin_info::from_metadata<T>(coin_metadata, remote_decimals);

        if (distributor_bytes.length() > 0) {
            let distributor = address::from_bytes(distributor_bytes);
            coin_management.add_distributor(distributor);
        };

        self.add_registered_coin<T>(token_id, coin_management, coin_info);
    }

    // We need an coin with zero supply that has the proper decimals and typing, and no Url.
    public fun give_unregistered_coin<T>(
        self: &mut ITS, treasury_cap: TreasuryCap<T>, mut coin_metadata: CoinMetadata<T>
    ) {
        assert!(treasury_cap.total_supply() == 0, ENonZeroTotalSupply);
        assert!(coin::get_icon_url(&coin_metadata).is_none(), EUnregisteredCoinHasUrl);

        treasury_cap.update_description(&mut coin_metadata, string::utf8(b""));

        let decimals = coin_metadata.get_decimals();
        let symbol = coin_metadata.get_symbol();

        let module_name = type_name::get_module(&type_name::get<T>());
        assert!(&module_name == &its_utils::get_module_from_symbol(&symbol), EModuleNameDoesNotMatchSymbol);

        let token_id = token_id::unregistered_token_id(&symbol, decimals);

        self.add_unregistered_coin<T>(token_id, treasury_cap, coin_metadata);
    }

    public fun mint_as_distributor<T>(
        self: &mut ITS,
        channel: &Channel,
        token_id: TokenId,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = channel.to_address();

        assert!(coin_management.is_distributor(distributor), ENotDistributor);

        coin_management.mint(amount, ctx)
    }

    public fun mint_to_as_distributor<T>(
        self: &mut ITS,
        channel: &Channel,
        token_id: TokenId,
        to: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let coin = mint_as_distributor<T>(self, channel, token_id, amount, ctx);
        transfer::public_transfer(coin, to);
    }

    public fun burn_as_distributor<T>(
        self: &mut ITS,
        channel: &Channel,
        token_id: TokenId,
        coin: Coin<T>
    ) {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = channel.to_address();

        assert!(coin_management.is_distributor<T>(distributor), ENotDistributor);

        coin_management.burn(coin);
    }

    // === Special Call Receiving
    public fun set_trusted_addresses(its: &mut ITS, governance: &Governance, approved_message: ApprovedMessage) {
        let (source_chain, _, source_address, payload) = channel::consume_approved_message(
            its.channel_mut(), approved_message
        );

        assert!(governance::is_governance(governance, source_chain, source_address), EUntrustedAddress);

        let mut reader = abi::new_reader(payload);
        let message_type = reader.read_u256();
        assert!(message_type == MESSAGE_TYPE_SET_TRUSTED_ADDRESSES, EInvalidMessageType);

        let mut bcs = bcs::new(reader.read_bytes());
        let trusted_addresses = trusted_addresses::peel(&mut bcs);

        assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);

        its.set_trusted_addresses(trusted_addresses);
    }

    // === Internal functions ===

    /// Decode an approved call and check that the source chain is trusted.
    fun decode_approved_message(self: &mut ITS, approved_message: ApprovedMessage): (String, vector<u8>) {
        let (
            mut source_chain,
            _,
            source_address,
            mut payload
        ) = self.channel_mut().consume_approved_message(approved_message);

        assert!(self.is_trusted_address(source_chain, source_address), EUntrustedAddress);

        let mut reader = abi::new_reader(payload);
        if (reader.read_u256() == MESSAGE_TYPE_RECEIVE_FROM_HUB) {
            assert!(source_chain.into_bytes() == ITS_HUB_CHAIN_NAME, EUntrustedChain);

            source_chain = ascii::string(reader.read_bytes());
            payload = reader.read_bytes();

            assert!(self.get_trusted_address(source_chain).into_bytes() == ITS_HUB_ROUTING_IDENTIFIER, EUntrustedChain);
        } else {
            assert!(source_chain.into_bytes() != ITS_HUB_CHAIN_NAME, EUntrustedChain);
        };

        (source_chain, payload)
    }

    /// Send a payload to a destination chain. The destination chain needs to have a trusted address.
    fun prepare_message(self: &mut ITS, mut destination_chain: String, mut payload: vector<u8>): MessageTicket {
        let mut destination_address = self.get_trusted_address(destination_chain);

        // Prevent sending directly to the ITS Hub chain. This is not supported yet, so fail early to prevent the user from having their funds stuck.
        assert!(destination_chain.into_bytes() != ITS_HUB_CHAIN_NAME, EUntrustedChain);

        // Check whether the ITS call should be routed via ITS hub for this destination chain
        if (destination_address.into_bytes() == ITS_HUB_ROUTING_IDENTIFIER) {
            let mut writer = abi::new_writer(3);
            writer.write_u256(MESSAGE_TYPE_SEND_TO_HUB);
            writer.write_bytes(destination_chain.into_bytes());
            writer.write_bytes(payload);
            payload = writer.into_bytes();
            destination_chain = ascii::string(ITS_HUB_CHAIN_NAME);
            destination_address = self.get_trusted_address(destination_chain);
        };

        gateway::prepare_message(self.channel_mut(), destination_chain, destination_address, payload)
    }

    // === Tests ===
    #[test_only]
    use its::coin::COIN;

    #[test_only]
    public fun create_unregistered_coin(self: &mut ITS, symbol: vector<u8>, decimals: u8, ctx: &mut TxContext) {
        let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let token_id = token_id::unregistered_token_id(&ascii::string(symbol), decimals);

        self.add_unregistered_coin(token_id, treasury_cap, coin_metadata);
    }

    #[test]
    fun test_register_coin() {
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        let coin_management = its::coin_management::new_locked();

        register_coin(&mut its, coin_info, coin_management);

        sui::test_utils::destroy(its);
    }

    #[test]
    fun test_deploy_remote_interchain_token() {
        let mut its = its::its::new_for_testing();
        let token_name = string::utf8(b"Name");
        let token_symbol = ascii::string(b"Symbol");
        let token_decimals = 10;
        let remote_decimals = 12;

        let coin_info = its::coin_info::from_info<COIN>(
            token_name,
            token_symbol,
            token_decimals,
            remote_decimals,
        );
        let coin_management = its::coin_management::new_locked();

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let destination_chain = ascii::string(b"Chain Name");
        let message_ticket = deploy_remote_interchain_token<COIN>(&mut its, token_id, destination_chain);
        
        let mut writer = abi::new_writer(6);

        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id.to_u256())
            .write_bytes(*token_name.as_bytes())
            .write_bytes(*token_symbol.as_bytes())
            .write_u256((token_decimals as u256))
            .write_bytes(vector::empty());

        assert!(message_ticket.source_id() == its.channel().to_address(), 0);
        assert!(message_ticket.destination_chain() == destination_chain, 1);
        assert!(message_ticket.destination_address() == its.get_trusted_address(destination_chain), 2);
        assert!(message_ticket.payload() == writer.into_bytes(), 3);
        assert!(message_ticket.version() == 0, 4);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(message_ticket);
    }

    #[test]
    fun test_deploy_interchain_token() {
        let ctx = &mut tx_context::dummy();
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        let scaling = coin_info.scaling();
        let coin_management = its::coin_management::new_locked();

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let amount = 1234;
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        let destination_chain = ascii::string(b"Chain Name");
        let destination_address = b"address";
        let metadata = b"";
        let source_channel = channel::new(ctx);
        let clock = sui::clock::create_for_testing(ctx);

        let interchain_transfer_ticket = prepare_interchain_transfer<COIN>(token_id, coin, destination_chain, destination_address, metadata, &source_channel);
        let message_ticket = send_interchain_transfer<COIN>(&mut its, interchain_transfer_ticket, &clock);
        let mut writer = abi::new_writer(6);

        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id.to_u256())
            .write_bytes(source_channel.to_address().to_bytes())
            .write_bytes(destination_address)
            .write_u256((amount as u256) * scaling)
            .write_bytes(b"");

        assert!(message_ticket.source_id() == its.channel().to_address(), 0);
        assert!(message_ticket.destination_chain() == destination_chain, 1);
        assert!(message_ticket.destination_address() == its.get_trusted_address(destination_chain), 2);
        assert!(message_ticket.payload() == writer.into_bytes(), 3);
        assert!(message_ticket.version() == 0, 4);

        clock.destroy_for_testing();
        source_channel.destroy();
        sui::test_utils::destroy(its);
        sui::test_utils::destroy(message_ticket);
    }

    #[test]
    fun test_receive_interchain_transfer() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        
        let amount = 1234;
        let mut coin_management = its::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_coin(coin, &clock);

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let message_source_address = ascii::string(b"Address");
        let its_source_address = b"Source Address";
        let destination_address = @0x1;
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id.to_u256())
            .write_bytes(its_source_address)
            .write_bytes(destination_address.to_bytes())
            .write_u256((amount as u256))
            .write_bytes(b"");
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            message_source_address,
            its.channel().to_address(),
            payload,
        );
        
        receive_interchain_transfer<COIN>(&mut its, approved_message, &clock, ctx);

        clock.destroy_for_testing();
        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMessageType)]
    fun test_receive_interchain_transfer_invalid_message_type() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        
        let amount = 1234;
        let mut coin_management = its::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_coin(coin, &clock);

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let message_source_address = ascii::string(b"Address");
        let its_source_address = b"Source Address";
        let destination_address = @0x1;
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id.to_u256())
            .write_bytes(its_source_address)
            .write_bytes(destination_address.to_bytes())
            .write_u256((amount as u256))
            .write_bytes(b"");
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            message_source_address,
            its.channel().to_address(),
            payload,
        );
        
        receive_interchain_transfer<COIN>(&mut its, approved_message, &clock, ctx);

        clock.destroy_for_testing();
        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = EInterchainTransferHasData)]
    fun test_receive_interchain_transfer_passed_data() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        
        let amount = 1234;
        let mut coin_management = its::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_coin(coin, &clock);

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let message_source_address = ascii::string(b"Address");
        let its_source_address = b"Source Address";
        let destination_address = @0x1;
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id.to_u256())
            .write_bytes(its_source_address)
            .write_bytes(destination_address.to_bytes())
            .write_u256((amount as u256))
            .write_bytes(b"some data");
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            message_source_address,
            its.channel().to_address(),
            payload,
        );
        
        receive_interchain_transfer<COIN>(&mut its, approved_message, &clock, ctx);

        clock.destroy_for_testing();
        sui::test_utils::destroy(its);
    }

    #[test]
    fun test_receive_interchain_transfer_with_data() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        let scaling = coin_info.scaling();
        
        let amount = 1234;
        let data = b"some_data";
        let mut coin_management = its::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_coin(coin, &clock);

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let message_source_address = ascii::string(b"Address");
        let its_source_address = b"Source Address";
        let channel = channel::new(ctx);
        let destination_address = channel.to_address();
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
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
            its.channel().to_address(),
            payload,
        );
         
        let (received_source_chain, received_source_address, received_data, received_coin) = receive_interchain_transfer_with_data<COIN>(&mut its, approved_message, &channel, &clock, ctx);

        assert!(received_source_chain == source_chain, 0);
        assert!(received_source_address == its_source_address, 1);
        assert!(received_data == data, 2);
        assert!(received_coin.value() == amount / (scaling as u64), 3);

        clock.destroy_for_testing();
        channel.destroy();
        sui::test_utils::destroy(its);
        sui::test_utils::destroy(received_coin);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMessageType)]
    fun test_receive_interchain_transfer_with_data_invalid_message_type() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        
        let amount = 1234;
        let mut coin_management = its::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_coin(coin, &clock);

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let message_source_address = ascii::string(b"Address");
        let its_source_address = b"Source Address";
        let channel = channel::new(ctx);
        let destination_address = channel.to_address();
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id.to_u256())
            .write_bytes(its_source_address)
            .write_bytes(destination_address.to_bytes())
            .write_u256((amount as u256))
            .write_bytes(b"some_data");
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            message_source_address,
            its.channel().to_address(),
            payload,
        );
         
        let (_, _, _, received_coin) = receive_interchain_transfer_with_data<COIN>(&mut its, approved_message, &channel, &clock, ctx);

        clock.destroy_for_testing();
        channel.destroy();
        sui::test_utils::destroy(its);
        sui::test_utils::destroy(received_coin);
    }

    #[test]
    #[expected_failure(abort_code = EWrongDestination)]
    fun test_receive_interchain_transfer_with_data_wrong_destination() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        
        let amount = 1234;
        let mut coin_management = its::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_coin(coin, &clock);

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let message_source_address = ascii::string(b"Address");
        let its_source_address = b"Source Address";
        let channel = channel::new(ctx);
        let destination_address = @0x1;
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id.to_u256())
            .write_bytes(its_source_address)
            .write_bytes(destination_address.to_bytes())
            .write_u256((amount as u256))
            .write_bytes(b"some_data");
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            message_source_address,
            its.channel().to_address(),
            payload,
        );
         
        let (_, _, _, received_coin) = receive_interchain_transfer_with_data<COIN>(&mut its, approved_message, &channel, &clock, ctx);

        clock.destroy_for_testing();
        channel.destroy();
        sui::test_utils::destroy(its);
        sui::test_utils::destroy(received_coin);
    }

    #[test]
    #[expected_failure(abort_code = EInterchainTransferHasNoData)]
    fun test_receive_interchain_transfer_with_data_no_data() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let coin_info = its::coin_info::from_info<COIN>(
            string::utf8(b"Name"),
            ascii::string(b"Symbol"),
            10,
            12,
        );
        
        let amount = 1234;
        let mut coin_management = its::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_coin(coin, &clock);

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let message_source_address = ascii::string(b"Address");
        let its_source_address = b"Source Address";
        let channel = channel::new(ctx);
        let destination_address = channel.to_address();
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id.to_u256())
            .write_bytes(its_source_address)
            .write_bytes(destination_address.to_bytes())
            .write_u256((amount as u256))
            .write_bytes(b"");
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            message_source_address,
            its.channel().to_address(),
            payload,
        );
         
        let (_, _, _, received_coin) = receive_interchain_transfer_with_data<COIN>(&mut its, approved_message, &channel, &clock, ctx);

        clock.destroy_for_testing();
        channel.destroy();
        sui::test_utils::destroy(its);
        sui::test_utils::destroy(received_coin);
    }

    #[test]
    fun test_receive_deploy_interchain_token() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let source_address = ascii::string(b"Address");
        let name = b"Token Name";
        let symbol = b"Symbol";
        let remote_decimals = 12;
        let decimals = if (remote_decimals > DECIMALS_CAP) DECIMALS_CAP else remote_decimals;
        let token_id: u256 = 1234;

        create_unregistered_coin(&mut its, symbol, decimals, ctx);
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id)
            .write_bytes(name)
            .write_bytes(symbol)
            .write_u256((remote_decimals as u256))
            .write_bytes(vector::empty());
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            its.channel().to_address(),
            payload,
        );
        
        receive_deploy_interchain_token<COIN>(&mut its, approved_message);

        clock.destroy_for_testing();
        sui::test_utils::destroy(its);
    }

    #[test]
    fun test_receive_deploy_interchain_token_with_distributor() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let source_address = ascii::string(b"Address");
        let name = b"Token Name";
        let symbol = b"Symbol";
        let remote_decimals = 8;
        let decimals = if (remote_decimals > DECIMALS_CAP) DECIMALS_CAP else remote_decimals;
        let token_id: u256 = 1234;
        let distributor = @0x1;

        create_unregistered_coin(&mut its, symbol, decimals, ctx);
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id)
            .write_bytes(name)
            .write_bytes(symbol)
            .write_u256((remote_decimals as u256))
            .write_bytes(distributor.to_bytes());
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            its.channel().to_address(),
            payload,
        );
        
        receive_deploy_interchain_token<COIN>(&mut its, approved_message);

        clock.destroy_for_testing();
        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMessageType)]
    fun test_receive_deploy_interchain_token_invalid_message_type() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut its = its::its::new_for_testing();

        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let source_address = ascii::string(b"Address");
        let name = b"Token Name";
        let symbol = b"Symbol";
        let remote_decimals = 8;
        let decimals = if (remote_decimals > DECIMALS_CAP) DECIMALS_CAP else remote_decimals;
        let token_id: u256 = 1234;

        create_unregistered_coin(&mut its, symbol, decimals, ctx);
        
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id)
            .write_bytes(name)
            .write_bytes(symbol)
            .write_u256((remote_decimals as u256))
            .write_bytes(b"");
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            its.channel().to_address(),
            payload,
        );
        
        receive_deploy_interchain_token<COIN>(&mut its, approved_message);

        clock.destroy_for_testing();
        sui::test_utils::destroy(its);
    }

    #[test]
    fun test_give_unregistered_coin() {
        let symbol = b"COIN";
        let decimals = 12;
        let ctx = &mut tx_context::dummy();
        let mut its = its::its::new_for_testing();

        let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);

        give_unregistered_coin<COIN>(&mut its, treasury_cap, coin_metadata);

        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = ENonZeroTotalSupply)]
    fun test_give_unregistered_coin_not_zero_total_supply() {
        let symbol = b"COIN";
        let decimals = 12;
        let ctx = &mut tx_context::dummy();
        let mut its = its::its::new_for_testing();

        let (mut treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let coin = treasury_cap.mint(1, ctx);

        give_unregistered_coin<COIN>(&mut its, treasury_cap, coin_metadata);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(coin);
    }

    #[test]
    #[expected_failure(abort_code = EUnregisteredCoinHasUrl)]
    fun test_give_unregistered_coin_with_url() {
        let name = b"Coin";
        let symbol = b"COIN";
        let decimals = 12;
        let ctx = &mut tx_context::dummy();
        let mut its = its::its::new_for_testing();
        let url = sui::url::new_unsafe_from_bytes(b"url");

        let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata_custom(name, symbol, decimals, option::some(url), ctx);

        give_unregistered_coin<COIN>(&mut its, treasury_cap, coin_metadata);

        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = EModuleNameDoesNotMatchSymbol)]
    fun test_give_unregistered_coin_module_name_missmatch() {
        let symbol = b"SYMBOL";
        let decimals = 12;
        let ctx = &mut tx_context::dummy();
        let mut its = its::its::new_for_testing();

        let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);

        give_unregistered_coin<COIN>(&mut its, treasury_cap, coin_metadata);

        sui::test_utils::destroy(its);
    }

    #[test]
    fun test_mint_as_distributor() {
        let mut its = its::its::new_for_testing();
        let ctx = &mut tx_context::dummy();
        let symbol = b"COIN";
        let decimals = 9;
        let remote_decimals = 18;

        let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let coin_info = its::coin_info::from_metadata<COIN>(
            coin_metadata,
            remote_decimals,
        );
        let mut coin_management = its::coin_management::new_with_cap(treasury_cap);

        let channel = channel::new(ctx);
        coin_management.add_distributor(channel.to_address());
        let amount = 1234;

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let coin = mint_as_distributor<COIN>(&mut its, &channel, token_id, amount, ctx);

        assert!(coin.value() == amount); 
        
        sui::test_utils::destroy(its);
        sui::test_utils::destroy(coin);
        channel.destroy();
    }

    #[test]
    #[expected_failure(abort_code = ENotDistributor)]
    fun test_mint_as_distributor_not_distributor() {
        let mut its = its::its::new_for_testing();
        let ctx = &mut tx_context::dummy();
        let symbol = b"COIN";
        let decimals = 9;
        let remote_decimals = 18;

        let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let coin_info = its::coin_info::from_metadata<COIN>(
            coin_metadata,
            remote_decimals,
        );
        let mut coin_management = its::coin_management::new_with_cap(treasury_cap);

        let channel = channel::new(ctx);
        coin_management.add_distributor(@0x1);
        let amount = 1234;

        let token_id = register_coin(&mut its, coin_info, coin_management);
        let coin = mint_as_distributor<COIN>(&mut its, &channel, token_id, amount, ctx);

        assert!(coin.value() == amount); 
        
        sui::test_utils::destroy(its);
        sui::test_utils::destroy(coin);
        channel.destroy();
    }

    #[test]
    fun test_mint_to_as_distributor() {
        let mut its = its::its::new_for_testing();
        let ctx = &mut tx_context::dummy();
        let symbol = b"COIN";
        let decimals = 9;
        let remote_decimals = 18;

        let (treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let coin_info = its::coin_info::from_metadata<COIN>(
            coin_metadata,
            remote_decimals,
        );
        let mut coin_management = its::coin_management::new_with_cap(treasury_cap);

        let channel = channel::new(ctx);
        coin_management.add_distributor(channel.to_address());
        let amount = 1234;

        let token_id = register_coin(&mut its, coin_info, coin_management);
        mint_to_as_distributor<COIN>(&mut its, &channel, token_id, @0x2, amount, ctx);
        
        sui::test_utils::destroy(its);
        channel.destroy();
    }

    #[test]
    fun test_burn_as_distributor() {
        let mut its = its::its::new_for_testing();
        let ctx = &mut tx_context::dummy();
        let symbol = b"COIN";
        let decimals = 9;
        let remote_decimals = 18;
        let amount = 1234;

        let (mut treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let coin = treasury_cap.mint(amount, ctx);
        let coin_info = its::coin_info::from_metadata<COIN>(
            coin_metadata,
            remote_decimals,
        );
        let mut coin_management = its::coin_management::new_with_cap(treasury_cap);

        let channel = channel::new(ctx);
        coin_management.add_distributor(channel.to_address());

        let token_id = register_coin(&mut its, coin_info, coin_management);
        burn_as_distributor<COIN>(&mut its, &channel, token_id, coin);
        
        sui::test_utils::destroy(its);
        channel.destroy();
    }

    #[test]
    #[expected_failure(abort_code = ENotDistributor)]
    fun test_burn_as_distributor_not_distributor() {
        let mut its = its::its::new_for_testing();
        let ctx = &mut tx_context::dummy();
        let symbol = b"COIN";
        let decimals = 9;
        let remote_decimals = 18;
        let amount = 1234;

        let (mut treasury_cap, coin_metadata) = its::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let coin = treasury_cap.mint(amount, ctx);
        let coin_info = its::coin_info::from_metadata<COIN>(
            coin_metadata,
            remote_decimals,
        );
        let mut coin_management = its::coin_management::new_with_cap(treasury_cap);

        let channel = channel::new(ctx);
        coin_management.add_distributor(@0x1);

        let token_id = register_coin(&mut its, coin_info, coin_management);
        burn_as_distributor<COIN>(&mut its, &channel, token_id, coin);
        
        sui::test_utils::destroy(its);
        channel.destroy();
    }

    #[test]
    fun test_set_trusted_address() {
        let mut its = its::its::new_for_testing();
        let trusted_source_chain = ascii::string(b"Axelar");
        let trusted_source_address = ascii::string(b"Trusted Address");
        let message_type = (123 as u256);
        let message_id = ascii::string(b"message_id");
        let ctx = &mut tx_context::dummy();

        let governance = governance::new_for_testing(
            trusted_source_chain,
            trusted_source_address,
            message_type,
            ctx,
        );

        let trusted_chains = vector[
            b"Ethereum",
            b"Avalance",
            b"Axelar",
        ];
        let trusted_addresses = vector[
            b"ethereum address",
            ITS_HUB_ROUTING_IDENTIFIER,
            b"hub address",
        ];
        let trusted_addresses_data = bcs::to_bytes(&its::trusted_addresses::new_for_testing(trusted_chains, trusted_addresses));

        let mut writer = abi::new_writer(2);
        writer
            .write_u256(MESSAGE_TYPE_SET_TRUSTED_ADDRESSES)
            .write_bytes(trusted_addresses_data);
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            trusted_source_chain,
            message_id,
            trusted_source_address,
            its.channel().to_address(),
            payload,
        );

        set_trusted_addresses(&mut its, &governance, approved_message);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(governance);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedAddress)]
    fun test_set_trusted_address_untrusted_address() {
        let mut its = its::its::new_for_testing();
        let trusted_source_chain = ascii::string(b"Axelar");
        let trusted_source_address = ascii::string(b"Trusted Address");
        let untrusted_source_address = ascii::string(b"Untrusted Address");
        let message_type = (123 as u256);
        let message_id = ascii::string(b"message_id");
        let ctx = &mut tx_context::dummy();

        let governance = governance::new_for_testing(
            trusted_source_chain,
            trusted_source_address,
            message_type,
            ctx,
        );

        let trusted_chains = vector[
            b"Ethereum",
            b"Avalance",
            b"Axelar",
        ];
        let trusted_addresses = vector[
            b"ethereum address",
            ITS_HUB_ROUTING_IDENTIFIER,
            b"hub address",
        ];
        let trusted_addresses_data = bcs::to_bytes(&its::trusted_addresses::new_for_testing(trusted_chains, trusted_addresses));

        let mut writer = abi::new_writer(2);
        writer
            .write_u256(MESSAGE_TYPE_SET_TRUSTED_ADDRESSES)
            .write_bytes(trusted_addresses_data);
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            trusted_source_chain,
            message_id,
            untrusted_source_address,
            its.channel().to_address(),
            payload,
        );

        set_trusted_addresses(&mut its, &governance, approved_message);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(governance);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMessageType)]
    fun test_set_trusted_address_invalid_message_type() {
        let mut its = its::its::new_for_testing();
        let trusted_source_chain = ascii::string(b"Axelar");
        let trusted_source_address = ascii::string(b"Trusted Address");
        let message_type = (123 as u256);
        let message_id = ascii::string(b"message_id");
        let ctx = &mut tx_context::dummy();

        let governance = governance::new_for_testing(
            trusted_source_chain,
            trusted_source_address,
            message_type,
            ctx,
        );

        let trusted_chains = vector[
            b"Ethereum",
            b"Avalance",
            b"Axelar",
        ];
        let trusted_addresses = vector[
            b"ethereum address",
            ITS_HUB_ROUTING_IDENTIFIER,
            b"hub address",
        ];
        let trusted_addresses_data = bcs::to_bytes(&its::trusted_addresses::new_for_testing(trusted_chains, trusted_addresses));

        let mut writer = abi::new_writer(2);
        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_bytes(trusted_addresses_data);
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            trusted_source_chain,
            message_id,
            trusted_source_address,
            its.channel().to_address(),
            payload,
        );

        set_trusted_addresses(&mut its, &governance, approved_message);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(governance);
    }

    #[test]
    #[expected_failure(abort_code = ERemainingData)]
    fun test_set_trusted_address_remaining_data() {
        let mut its = its::its::new_for_testing();
        let trusted_source_chain = ascii::string(b"Axelar");
        let trusted_source_address = ascii::string(b"Trusted Address");
        let message_type = (123 as u256);
        let message_id = ascii::string(b"message_id");
        let ctx = &mut tx_context::dummy();

        let governance = governance::new_for_testing(
            trusted_source_chain,
            trusted_source_address,
            message_type,
            ctx,
        );

        let trusted_chains = vector[
            b"Ethereum",
            b"Avalance",
            b"Axelar",
        ];
        let trusted_addresses = vector[
            b"ethereum address",
            ITS_HUB_ROUTING_IDENTIFIER,
            b"hub address",
        ];
        let mut trusted_addresses_data = bcs::to_bytes(&its::trusted_addresses::new_for_testing(trusted_chains, trusted_addresses));
        trusted_addresses_data.push_back(0);

        let mut writer = abi::new_writer(2);
        writer
            .write_u256(MESSAGE_TYPE_SET_TRUSTED_ADDRESSES)
            .write_bytes(trusted_addresses_data);
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            trusted_source_chain,
            message_id,
            trusted_source_address,
            its.channel().to_address(),
            payload,
        );

        set_trusted_addresses(&mut its, &governance, approved_message);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(governance);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedAddress)]
    fun test_decode_approved_message_untrusted_address() {
        let mut its = its::its::new_for_testing();
        let source_chain = ascii::string(b"Chain Name");
        let source_address = ascii::string(b"Untusted Address");
        let message_id = ascii::string(b"message_id");

        let payload = b"payload";

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            its.channel().to_address(),
            payload,
        );

        decode_approved_message(&mut its, approved_message);

        sui::test_utils::destroy(its);
    }

    #[test]
    fun test_decode_approved_message_axelar_hub_sender() {
        let mut its = its::its::new_for_testing();
        let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
        let source_address = ascii::string(b"Address");
        let message_id = ascii::string(b"message_id");
        let origin_chain = ascii::string(b"Source Chain");
        let payload = b"payload";

        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
        writer.write_bytes(origin_chain.into_bytes());
        writer.write_bytes(payload);
        let payload = writer.into_bytes();

        its.set_trusted_address(source_chain, source_address);
        its.set_trusted_address(origin_chain, ascii::string(ITS_HUB_ROUTING_IDENTIFIER));

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            its.channel().to_address(),
            payload,
        );

        decode_approved_message(&mut its, approved_message);

        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedChain)]
    fun test_decode_approved_message_sender_not_hub() {
        let mut its = its::its::new_for_testing();
        let source_chain = ascii::string(b"Chain Name");
        let source_address = ascii::string(b"Address");
        let message_id = ascii::string(b"message_id");

        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
        writer.write_bytes(b"Source Chain");
        writer.write_bytes(b"payload");
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            its.channel().to_address(),
            payload,
        );

        decode_approved_message(&mut its, approved_message);

        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedChain)]
    fun test_decode_approved_message_origin_not_hub_routed() {
        let mut its = its::its::new_for_testing();
        let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
        let source_address = ascii::string(b"Address");
        let message_id = ascii::string(b"message_id");
        let origin_chain = ascii::string(b"Source Chain");
        let origin_trusted_address = ascii::string(b"Origin Trusted Address");
        let payload = b"payload";

        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
        writer.write_bytes(origin_chain.into_bytes());
        writer.write_bytes(payload);
        let payload = writer.into_bytes();

        its.set_trusted_address(source_chain, source_address);
        its.set_trusted_address(origin_chain, origin_trusted_address);

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            its.channel().to_address(),
            payload,
        );

        decode_approved_message(&mut its, approved_message);

        sui::test_utils::destroy(its);
    }

    #[test]
    fun test_send_payload_to_hub() {
        let mut its = its::its::new_for_testing();
        let destination_chain = ascii::string(b"Destination Chain");
        let hub_address = ascii::string(b"Address");

        let payload = b"payload";

        its.set_trusted_address(ascii::string(ITS_HUB_CHAIN_NAME), hub_address);
        its.set_trusted_address(destination_chain, ascii::string(ITS_HUB_ROUTING_IDENTIFIER));

        let message_ticket = prepare_message(&mut its, destination_chain, payload);



        sui::test_utils::destroy(its);
        sui::test_utils::destroy(message_ticket);
    }
}
