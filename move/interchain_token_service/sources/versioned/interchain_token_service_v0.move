module interchain_token_service::interchain_token_service_v0 {
    use abi::abi::{Self, AbiReader};
    use axelar_gateway::{bytes32::{Self, Bytes32}, channel::{Channel, ApprovedMessage}, gateway, message_ticket::MessageTicket};
    use interchain_token_service::{
        coin_data::{Self, CoinData},
        coin_info::{Self, CoinInfo},
        coin_management::{Self, CoinManagement},
        events,
        interchain_transfer_ticket::InterchainTransferTicket,
        token_id::{Self, TokenId, UnregisteredTokenId},
        trusted_chains::{Self, TrustedChains},
        unregistered_coin_data::{Self, UnregisteredCoinData},
        utils as its_utils
    };
    use relayer_discovery::discovery::RelayerDiscovery;
    use std::{ascii::{Self, String}, string, type_name::{Self, TypeName}};
    use sui::{
        address,
        bag::{Self, Bag},
        clock::Clock,
        coin::{Self, TreasuryCap, CoinMetadata, Coin},
        hash::keccak256,
        table::{Self, Table}
    };
    use version_control::version_control::VersionControl;

    // ------
    // Errors
    // ------
    #[error]
    const EUnregisteredCoin: vector<u8> = b"trying to find a coin that doesn't exist";
    #[error]
    const EUntrustedAddress: vector<u8> = b"the sender that sent this message is not trusted";
    #[error]
    const EInvalidMessageType: vector<u8> = b"the message type received is not supported";
    #[error]
    const EWrongDestination: vector<u8> = b"the channel trying to receive this call is not the destination";
    #[error]
    const EInterchainTransferHasData: vector<u8> = b"interchain transfer with data trying to be processed as an interchain transfer";
    #[error]
    const EInterchainTransferHasNoData: vector<u8> = b"interchain transfer trying to be proccessed as an interchain transfer";
    #[error]
    const EModuleNameDoesNotMatchSymbol: vector<u8> = b"the module name does not match the symbol";
    #[error]
    const ENotDistributor: vector<u8> = b"only the distributor can mint";
    #[error]
    const ENonZeroTotalSupply: vector<u8> = b"trying to give a token that has had some supply already minted";
    #[error]
    const EUnregisteredCoinHasUrl: vector<u8> = b"the interchain token that is being registered has a URL";
    #[error]
    const EUntrustedChain: vector<u8> = b"the chain is not trusted";
    #[error]
    const ENewerTicket: vector<u8> = b"cannot proccess newer tickets";
    #[error]
    const EOverflow: vector<u8> = b"cannot receive more than 2^64-1 coins";

    // === MESSAGE TYPES ===
    const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
    const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
    // onst MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;
    const MESSAGE_TYPE_SEND_TO_HUB: u256 = 3;
    const MESSAGE_TYPE_RECEIVE_FROM_HUB: u256 = 4;

    // === HUB CONSTANTS ===
    // Chain name for Axelar. This is used for routing InterchainTokenService calls via InterchainTokenService hub on
    // Axelar.
    const ITS_HUB_CHAIN_NAME: vector<u8> = b"axelar";

    // -----
    // Types
    // -----
    public struct InterchainTokenService_v0 has store {
        channel: Channel,
        trusted_chains: TrustedChains,
        unregistered_coin_types: Table<UnregisteredTokenId, TypeName>,
        unregistered_coins: Bag,
        registered_coin_types: Table<TokenId, TypeName>,
        registered_coins: Bag,
        relayer_discovery_id: ID,
        its_hub_address: String,
        chain_name_hash: Bytes32,
        version_control: VersionControl,
    }

    // -----------------
    // Package Functions
    // -----------------
    public(package) fun new(
        version_control: VersionControl,
        chain_name: String,
        its_hub_address: String,
        ctx: &mut TxContext,
    ): InterchainTokenService_v0 {
        InterchainTokenService_v0 {
            channel: axelar_gateway::channel::new(ctx),
            trusted_chains: trusted_chains::new(
                ctx,
            ),
            registered_coins: bag::new(ctx),
            registered_coin_types: table::new(ctx),
            unregistered_coins: bag::new(ctx),
            unregistered_coin_types: table::new(ctx),
            its_hub_address,
            chain_name_hash: bytes32::from_bytes(keccak256(&chain_name.into_bytes())),
            relayer_discovery_id: object::id_from_address(@0x0),
            version_control,
        }
    }

    public(package) fun unregistered_coin_type(self: &InterchainTokenService_v0, symbol: &String, decimals: u8): &TypeName {
        let key = token_id::unregistered_token_id(symbol, decimals);

        assert!(self.unregistered_coin_types.contains(key), EUnregisteredCoin);
        &self.unregistered_coin_types[key]
    }

    public(package) fun registered_coin_type(self: &InterchainTokenService_v0, token_id: TokenId): &TypeName {
        assert!(self.registered_coin_types.contains(token_id), EUnregisteredCoin);
        &self.registered_coin_types[token_id]
    }

    public(package) fun channel_address(self: &InterchainTokenService_v0): address {
        self.channel.to_address()
    }

    public(package) fun set_relayer_discovery_id(self: &mut InterchainTokenService_v0, relayer_discovery: &RelayerDiscovery) {
        self.relayer_discovery_id = object::id(relayer_discovery);
    }

    public(package) fun relayer_discovery_id(self: &InterchainTokenService_v0): ID {
        self.relayer_discovery_id
    }

    public(package) fun add_trusted_chain(self: &mut InterchainTokenService_v0, chain_name: String) {
        self.trusted_chains.add(chain_name);
    }

    public(package) fun remove_trusted_chain(self: &mut InterchainTokenService_v0, chain_name: String) {
        self.trusted_chains.remove(chain_name);
    }

    public(package) fun add_trusted_chains(self: &mut InterchainTokenService_v0, chain_names: vector<String>) {
        chain_names.do!(
            |chain_name| self.add_trusted_chain(
                chain_name,
            ),
        );
    }

    public(package) fun remove_trusted_chains(self: &mut InterchainTokenService_v0, chain_names: vector<String>) {
        chain_names.do!(
            |chain_name| self.remove_trusted_chain(
                chain_name,
            ),
        );
    }

    public(package) fun channel(self: &InterchainTokenService_v0): &Channel {
        &self.channel
    }

    public(package) fun version_control(self: &InterchainTokenService_v0): &VersionControl {
        &self.version_control
    }

    public(package) fun register_coin<T>(
        self: &mut InterchainTokenService_v0,
        coin_info: CoinInfo<T>,
        coin_management: CoinManagement<T>,
    ): TokenId {
        let token_id = token_id::from_coin_data(&self.chain_name_hash, &coin_info, &coin_management);

        self.add_registered_coin(token_id, coin_management, coin_info);

        token_id
    }

    public(package) fun deploy_remote_interchain_token<T>(
        self: &InterchainTokenService_v0,
        token_id: TokenId,
        destination_chain: String,
    ): MessageTicket {
        let coin_info = self.coin_info<T>(token_id);

        let name = coin_info.name();
        let symbol = coin_info.symbol();
        let decimals = coin_info.decimals();

        let mut writer = abi::new_writer(6);

        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id.to_u256())
            .write_bytes(*name.as_bytes())
            .write_bytes(*symbol.as_bytes())
            .write_u256((decimals as u256))
            .write_bytes(vector::empty());

        events::interchain_token_deployment_started<T>(
            token_id,
            name,
            symbol,
            decimals,
            destination_chain,
        );

        let payload = writer.into_bytes();

        self.prepare_hub_message(payload, destination_chain)
    }

    public(package) fun send_interchain_transfer<T>(
        self: &mut InterchainTokenService_v0,
        ticket: InterchainTransferTicket<T>,
        current_version: u64,
        clock: &Clock,
    ): MessageTicket {
        let (token_id, balance, source_address, destination_chain, destination_address, metadata, version) = ticket.destroy();
        assert!(version <= current_version, ENewerTicket);

        let amount = self.coin_management_mut(token_id).take_balance(balance, clock);
        let (_version, data) = its_utils::decode_metadata(metadata);
        let mut writer = abi::new_writer(6);

        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id.to_u256())
            .write_bytes(source_address.to_bytes())
            .write_bytes(destination_address)
            .write_u256((amount as u256))
            .write_bytes(data);

        events::interchain_transfer<T>(
            token_id,
            source_address,
            destination_chain,
            destination_address,
            amount,
            &data,
        );

        let payload = writer.into_bytes();

        self.prepare_hub_message(payload, destination_chain)
    }

    public(package) fun receive_interchain_transfer<T>(
        self: &mut InterchainTokenService_v0,
        approved_message: ApprovedMessage,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let (source_chain, payload, message_id) = self.decode_approved_message(
            approved_message,
        );
        let mut reader = abi::new_reader(payload);
        assert!(reader.read_u256() == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);

        let token_id = token_id::from_u256(reader.read_u256());
        let source_address = reader.read_bytes();
        let destination_address = address::from_bytes(reader.read_bytes());
        let amount = read_amount(&mut reader);
        let data = reader.read_bytes();

        assert!(data.is_empty(), EInterchainTransferHasData);

        let coin = self.coin_management_mut(token_id).give_coin<T>(amount, clock, ctx);

        transfer::public_transfer(coin, destination_address);

        events::interchain_transfer_received<T>(
            message_id,
            token_id,
            source_chain,
            source_address,
            destination_address,
            amount,
            &b"",
        );
    }

    public(package) fun receive_interchain_transfer_with_data<T>(
        self: &mut InterchainTokenService_v0,
        approved_message: ApprovedMessage,
        channel: &Channel,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (String, vector<u8>, vector<u8>, Coin<T>) {
        let (source_chain, payload, message_id) = self.decode_approved_message(
            approved_message,
        );
        let mut reader = abi::new_reader(payload);
        assert!(reader.read_u256() == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);

        let token_id = token_id::from_u256(reader.read_u256());

        let source_address = reader.read_bytes();
        let destination_address = address::from_bytes(reader.read_bytes());
        let amount = read_amount(&mut reader);
        let data = reader.read_bytes();

        assert!(destination_address == channel.to_address(), EWrongDestination);
        assert!(!data.is_empty(), EInterchainTransferHasNoData);

        let coin = self.coin_management_mut(token_id).give_coin(amount, clock, ctx);

        events::interchain_transfer_received<T>(
            message_id,
            token_id,
            source_chain,
            source_address,
            destination_address,
            amount,
            &data,
        );

        (source_chain, source_address, data, coin)
    }

    public(package) fun receive_deploy_interchain_token<T>(self: &mut InterchainTokenService_v0, approved_message: ApprovedMessage) {
        let (_, payload, _) = self.decode_approved_message(approved_message);
        let mut reader = abi::new_reader(payload);
        assert!(reader.read_u256() == MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, EInvalidMessageType);

        let token_id = token_id::from_u256(reader.read_u256());
        let name = string::utf8(reader.read_bytes());
        let symbol = ascii::string(reader.read_bytes());
        let decimals = (reader.read_u256() as u8);
        let distributor_bytes = reader.read_bytes();
        let (treasury_cap, mut coin_metadata) = self.remove_unregistered_coin<T>(
            token_id::unregistered_token_id(&symbol, decimals),
        );

        treasury_cap.update_name(&mut coin_metadata, name);

        let mut coin_management = coin_management::new_with_cap<T>(treasury_cap);
        let coin_info = coin_info::from_metadata<T>(coin_metadata);

        if (distributor_bytes.length() > 0) {
            let distributor = address::from_bytes(distributor_bytes);
            coin_management.add_distributor(distributor);
        };

        self.add_registered_coin<T>(token_id, coin_management, coin_info);
    }

    public(package) fun give_unregistered_coin<T>(
        self: &mut InterchainTokenService_v0,
        treasury_cap: TreasuryCap<T>,
        mut coin_metadata: CoinMetadata<T>,
    ) {
        assert!(treasury_cap.total_supply() == 0, ENonZeroTotalSupply);
        assert!(coin::get_icon_url(&coin_metadata).is_none(), EUnregisteredCoinHasUrl);

        treasury_cap.update_description(&mut coin_metadata, string::utf8(b""));

        let decimals = coin_metadata.get_decimals();
        let symbol = coin_metadata.get_symbol();

        let module_name = type_name::get_module(&type_name::get<T>());
        assert!(&module_name == &its_utils::module_from_symbol(&symbol), EModuleNameDoesNotMatchSymbol);

        let token_id = token_id::unregistered_token_id(&symbol, decimals);

        self.add_unregistered_coin<T>(token_id, treasury_cap, coin_metadata);

        events::unregistered_coin_received<T>(
            token_id,
            symbol,
            decimals,
        );
    }

    public(package) fun mint_as_distributor<T>(
        self: &mut InterchainTokenService_v0,
        channel: &Channel,
        token_id: TokenId,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = channel.to_address();

        assert!(coin_management.is_distributor(distributor), ENotDistributor);

        coin_management.mint(amount, ctx)
    }

    public(package) fun mint_to_as_distributor<T>(
        self: &mut InterchainTokenService_v0,
        channel: &Channel,
        token_id: TokenId,
        to: address,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = channel.to_address();

        assert!(coin_management.is_distributor(distributor), ENotDistributor);

        let coin = coin_management.mint(amount, ctx);

        transfer::public_transfer(coin, to);
    }

    public(package) fun burn_as_distributor<T>(self: &mut InterchainTokenService_v0, channel: &Channel, token_id: TokenId, coin: Coin<T>) {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = channel.to_address();

        assert!(coin_management.is_distributor<T>(distributor), ENotDistributor);

        coin_management.burn(coin.into_balance());
    }

    public(package) fun set_flow_limit_as_token_operator<T>(
        self: &mut InterchainTokenService_v0,
        channel: &Channel,
        token_id: TokenId,
        limit: Option<u64>,
    ) {
        self.coin_management_mut<T>(token_id).set_flow_limit(channel, limit);
        events::flow_limit_set<T>(token_id, limit);
    }

    public(package) fun set_flow_limit<T>(self: &mut InterchainTokenService_v0, token_id: TokenId, limit: Option<u64>) {
        self.coin_management_mut<T>(token_id).set_flow_limit_internal(limit);
        events::flow_limit_set<T>(token_id, limit);
    }

    public(package) fun transfer_distributorship<T>(
        self: &mut InterchainTokenService_v0,
        channel: &Channel,
        token_id: TokenId,
        new_distributor: Option<address>,
    ) {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = channel.to_address();

        assert!(coin_management.is_distributor<T>(distributor), ENotDistributor);

        coin_management.update_distributorship(new_distributor);

        events::distributorship_transfered<T>(token_id, new_distributor);
    }

    public(package) fun transfer_operatorship<T>(
        self: &mut InterchainTokenService_v0,
        channel: &Channel,
        token_id: TokenId,
        new_operator: Option<address>,
    ) {
        let coin_management = self.coin_management_mut<T>(token_id);

        coin_management.update_operatorship<T>(channel, new_operator);

        events::operatorship_transfered<T>(token_id, new_operator);
    }

    public(package) fun allow_function(self: &mut InterchainTokenService_v0, version: u64, function_name: String) {
        self.version_control.allow_function(version, function_name);
    }

    public(package) fun disallow_function(self: &mut InterchainTokenService_v0, version: u64, function_name: String) {
        self.version_control.disallow_function(version, function_name);
    }

    public(package) fun coin_data<T>(self: &InterchainTokenService_v0, token_id: TokenId): &CoinData<T> {
        assert!(self.registered_coins.contains(token_id), EUnregisteredCoin);
        &self.registered_coins[token_id]
    }

    // -----------------
    // Private Functions
    // -----------------

    fun coin_info<T>(self: &InterchainTokenService_v0, token_id: TokenId): &CoinInfo<T> {
        coin_data<T>(self, token_id).coin_info()
    }

    fun is_trusted_chain(self: &InterchainTokenService_v0, source_chain: String): bool {
        self.trusted_chains.is_trusted(source_chain)
    }

    fun coin_management_mut<T>(self: &mut InterchainTokenService_v0, token_id: TokenId): &mut CoinManagement<T> {
        let coin_data: &mut CoinData<T> = &mut self.registered_coins[token_id];
        coin_data.coin_management_mut()
    }

    fun add_unregistered_coin<T>(
        self: &mut InterchainTokenService_v0,
        token_id: UnregisteredTokenId,
        treasury_cap: TreasuryCap<T>,
        coin_metadata: CoinMetadata<T>,
    ) {
        self
            .unregistered_coins
            .add(
                token_id,
                unregistered_coin_data::new(
                    treasury_cap,
                    coin_metadata,
                ),
            );

        let type_name = type_name::get<T>();
        add_unregistered_coin_type(self, token_id, type_name);
    }

    fun remove_unregistered_coin<T>(
        self: &mut InterchainTokenService_v0,
        token_id: UnregisteredTokenId,
    ): (TreasuryCap<T>, CoinMetadata<T>) {
        let unregistered_coins: UnregisteredCoinData<T> = self.unregistered_coins.remove(token_id);
        let (treasury_cap, coin_metadata) = unregistered_coins.destroy();

        remove_unregistered_coin_type(self, token_id);

        (treasury_cap, coin_metadata)
    }

    fun add_unregistered_coin_type(self: &mut InterchainTokenService_v0, token_id: UnregisteredTokenId, type_name: TypeName) {
        self.unregistered_coin_types.add(token_id, type_name);
    }

    fun remove_unregistered_coin_type(self: &mut InterchainTokenService_v0, token_id: UnregisteredTokenId): TypeName {
        self.unregistered_coin_types.remove(token_id)
    }

    fun add_registered_coin_type(self: &mut InterchainTokenService_v0, token_id: TokenId, type_name: TypeName) {
        self.registered_coin_types.add(token_id, type_name);
    }

    fun add_registered_coin<T>(
        self: &mut InterchainTokenService_v0,
        token_id: TokenId,
        coin_management: CoinManagement<T>,
        coin_info: CoinInfo<T>,
    ) {
        self
            .registered_coins
            .add(
                token_id,
                coin_data::new(
                    coin_management,
                    coin_info,
                ),
            );

        let type_name = type_name::get<T>();
        add_registered_coin_type(self, token_id, type_name);

        events::coin_registered<T>(
            token_id,
        );
    }

    fun prepare_hub_message(self: &InterchainTokenService_v0, mut payload: vector<u8>, destination_chain: String): MessageTicket {
        assert!(self.is_trusted_chain(destination_chain), EUntrustedChain);

        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_SEND_TO_HUB);
        writer.write_bytes(destination_chain.into_bytes());
        writer.write_bytes(payload);
        payload = writer.into_bytes();

        self.prepare_message(payload)
    }

    /// Send a payload to a destination chain. The destination chain needs to have a
    /// trusted address.
    fun prepare_message(self: &InterchainTokenService_v0, payload: vector<u8>): MessageTicket {
        gateway::prepare_message(
            &self.channel,
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            self.its_hub_address,
            payload,
        )
    }

    /// Decode an approved call and check that the source chain is trusted.
    fun decode_approved_message(self: &InterchainTokenService_v0, approved_message: ApprovedMessage): (String, vector<u8>, String) {
        let (source_chain, message_id, source_address, payload) = self.channel.consume_approved_message(approved_message);

        assert!(source_chain.into_bytes() == ITS_HUB_CHAIN_NAME, EUntrustedChain);
        assert!(source_address == self.its_hub_address, EUntrustedAddress);

        let mut reader = abi::new_reader(payload);
        assert!(reader.read_u256() == MESSAGE_TYPE_RECEIVE_FROM_HUB, EInvalidMessageType);

        let source_chain = ascii::string(reader.read_bytes());
        let payload = reader.read_bytes();

        assert!(self.is_trusted_chain(source_chain), EUntrustedChain);

        (source_chain, payload, message_id)
    }

    fun read_amount(reader: &mut AbiReader): u64 {
        let amount = std::macros::try_as_u64!(reader.read_u256());
        assert!(amount.is_some(), EOverflow);
        amount.destroy_some()
    }

    // ---------
    // Test Only
    // ---------
    #[test_only]
    use axelar_gateway::channel;
    #[test_only]
    use interchain_token_service::coin::COIN;

    // The address of the ITS HUB.
    #[test_only]
    const ITS_HUB_ADDRESS: vector<u8> = b"hub_address";

    #[test_only]
    fun create_for_testing(ctx: &mut TxContext): InterchainTokenService_v0 {
        let mut self = new(
            version_control::version_control::new(vector[]),
            b"chain name".to_ascii_string(),
            ITS_HUB_ADDRESS.to_ascii_string(),
            ctx,
        );

        self.add_trusted_chain(
            std::ascii::string(b"Chain Name"),
        );

        self
    }

    #[test_only]
    public fun create_unregistered_coin(self: &mut InterchainTokenService_v0, symbol: vector<u8>, decimals: u8, ctx: &mut TxContext) {
        let (treasury_cap, coin_metadata) = interchain_token_service::coin::create_treasury_and_metadata(
            symbol,
            decimals,
            ctx,
        );
        let token_id = token_id::unregistered_token_id(
            &ascii::string(symbol),
            decimals,
        );

        self.add_unregistered_coin(token_id, treasury_cap, coin_metadata);
    }

    #[test_only]
    public(package) fun add_unregistered_coin_type_for_testing(
        self: &mut InterchainTokenService_v0,
        token_id: UnregisteredTokenId,
        type_name: TypeName,
    ) {
        self.add_unregistered_coin_type(token_id, type_name);
    }

    #[test_only]
    public(package) fun remove_unregistered_coin_type_for_testing(
        self: &mut InterchainTokenService_v0,
        token_id: UnregisteredTokenId,
    ): TypeName {
        self.remove_unregistered_coin_type(token_id)
    }

    #[test_only]
    public(package) fun add_registered_coin_type_for_testing(self: &mut InterchainTokenService_v0, token_id: TokenId, type_name: TypeName) {
        self.add_registered_coin_type(token_id, type_name);
    }

    #[test_only]
    public(package) fun remove_registered_coin_type_for_testing(self: &mut InterchainTokenService_v0, token_id: TokenId): TypeName {
        self.remove_registered_coin_type_for_testing(token_id)
    }

    #[test_only]
    public(package) fun wrap_payload_sending(payload: vector<u8>, destination_chain: String): vector<u8> {
        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_SEND_TO_HUB);
        writer.write_bytes(destination_chain.into_bytes());
        writer.write_bytes(payload);
        writer.into_bytes()
    }

    #[test_only]
    public fun wrap_payload_receiving(payload: vector<u8>, source_chain: String): vector<u8> {
        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
        writer.write_bytes(source_chain.into_bytes());
        writer.write_bytes(payload);
        writer.into_bytes()
    }

    #[test_only]
    public(package) fun chain_name_hash(self: &InterchainTokenService_v0): Bytes32 {
        self.chain_name_hash
    }

    // -----
    // Tests
    // -----
    #[test]
    fun test_decode_approved_message_axelar_hub_sender() {
        let ctx = &mut tx_context::dummy();
        let mut self = create_for_testing(ctx);

        let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
        let source_address = ascii::string(ITS_HUB_ADDRESS);
        let message_id = ascii::string(b"message_id");
        let origin_chain = ascii::string(b"Source Chain");
        let payload = b"payload";

        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
        writer.write_bytes(origin_chain.into_bytes());
        writer.write_bytes(payload);
        let payload = writer.into_bytes();

        self.add_trusted_chain(
            origin_chain,
        );

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            self.channel.to_address(),
            payload,
        );

        self.decode_approved_message(approved_message);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedChain)]
    fun test_decode_approved_message_sender_not_hub() {
        let ctx = &mut tx_context::dummy();
        let self = create_for_testing(ctx);

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
            self.channel.to_address(),
            payload,
        );

        self.decode_approved_message(approved_message);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedAddress)]
    fun test_decode_approved_message_sender_not_hub_address() {
        let ctx = &mut tx_context::dummy();
        let self = create_for_testing(ctx);

        let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
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
            self.channel.to_address(),
            payload,
        );

        self.decode_approved_message(approved_message);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedChain)]
    fun test_decode_approved_message_origin_not_hub_routed() {
        let ctx = &mut tx_context::dummy();
        let self = create_for_testing(ctx);

        let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
        let source_address = ascii::string(ITS_HUB_ADDRESS);
        let message_id = ascii::string(b"message_id");
        let origin_chain = ascii::string(b"Source Chain");
        let payload = b"payload";

        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
        writer.write_bytes(origin_chain.into_bytes());
        writer.write_bytes(payload);
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            self.channel.to_address(),
            payload,
        );

        self.decode_approved_message(approved_message);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedChain)]
    fun test_decode_approved_message_untrusted_chain() {
        let ctx = &mut tx_context::dummy();
        let self = create_for_testing(ctx);

        let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
        let source_address = ascii::string(ITS_HUB_ADDRESS);
        let message_id = ascii::string(b"message_id");
        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB);
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            self.channel.to_address(),
            payload,
        );

        self.decode_approved_message(approved_message);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMessageType)]
    fun test_decode_approved_message_invalid_message_type() {
        let ctx = &mut tx_context::dummy();
        let self = create_for_testing(ctx);

        let source_chain = ascii::string(ITS_HUB_CHAIN_NAME);
        let source_address = ascii::string(ITS_HUB_ADDRESS);
        let message_id = ascii::string(b"message_id");
        let mut writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER);
        let payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            source_chain,
            message_id,
            source_address,
            self.channel.to_address(),
            payload,
        );

        self.decode_approved_message(approved_message);

        sui::test_utils::destroy(self);
    }

    #[test]
    fun test_prepare_message_to_hub() {
        let ctx = &mut tx_context::dummy();
        let mut self = create_for_testing(ctx);

        let destination_chain = ascii::string(b"Destination Chain");

        let mut payload = b"payload";

        self.add_trusted_chain(destination_chain);

        payload = wrap_payload_sending(payload, destination_chain);

        let message_ticket = self.prepare_message(payload);

        assert!(message_ticket.destination_chain() == ITS_HUB_CHAIN_NAME.to_ascii_string());
        assert!(message_ticket.destination_address() == ITS_HUB_ADDRESS.to_ascii_string());

        sui::test_utils::destroy(self);
        sui::test_utils::destroy(message_ticket);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMessageType)]
    fun test_receive_interchain_transfer_invalid_message_type() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut self = create_for_testing(ctx);

        let coin_info =
            interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );

        let amount = 1234;
        let mut coin_management = interchain_token_service::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_balance(coin.into_balance(), &clock);

        let token_id = self.register_coin(coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
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
        let mut payload = writer.into_bytes();
        writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB).write_bytes(source_chain.into_bytes()).write_bytes(payload);
        payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            message_id,
            ITS_HUB_ADDRESS.to_ascii_string(),
            self.channel.to_address(),
            payload,
        );

        self.receive_interchain_transfer<COIN>(approved_message, &clock, ctx);

        clock.destroy_for_testing();
        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EInterchainTransferHasData)]
    fun test_receive_interchain_transfer_passed_data() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut self = create_for_testing(ctx);

        let coin_info =
            interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );

        let amount = 1234;
        let mut coin_management = interchain_token_service::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_balance(coin.into_balance(), &clock);

        let token_id = self.register_coin(coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
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
        let mut payload = writer.into_bytes();
        writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB).write_bytes(source_chain.into_bytes()).write_bytes(payload);
        payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            message_id,
            ITS_HUB_ADDRESS.to_ascii_string(),
            self.channel.to_address(),
            payload,
        );

        self.receive_interchain_transfer<COIN>(approved_message, &clock, ctx);

        clock.destroy_for_testing();
        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMessageType)]
    fun test_receive_interchain_transfer_with_data_invalid_message_type() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut self = create_for_testing(ctx);
        let coin_info =
            interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );

        let amount = 1234;
        let mut coin_management = interchain_token_service::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_balance(coin.into_balance(), &clock);

        let token_id = self.register_coin(coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
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
        let mut payload = writer.into_bytes();
        writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB).write_bytes(source_chain.into_bytes()).write_bytes(payload);
        payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            message_id,
            ITS_HUB_ADDRESS.to_ascii_string(),
            self.channel.to_address(),
            payload,
        );

        let (_, _, _, received_coin) = self.receive_interchain_transfer_with_data<COIN>(
            approved_message,
            &channel,
            &clock,
            ctx,
        );

        clock.destroy_for_testing();
        channel.destroy();
        sui::test_utils::destroy(self);
        sui::test_utils::destroy(received_coin);
    }

    #[test]
    #[expected_failure(abort_code = EWrongDestination)]
    fun test_receive_interchain_transfer_with_data_wrong_destination() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut self = create_for_testing(ctx);

        let coin_info =
            interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );

        let amount = 1234;
        let mut coin_management = interchain_token_service::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_balance(coin.into_balance(), &clock);

        let token_id = self.register_coin(coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
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
        let mut payload = writer.into_bytes();
        writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB).write_bytes(source_chain.into_bytes()).write_bytes(payload);
        payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            message_id,
            ITS_HUB_ADDRESS.to_ascii_string(),
            self.channel.to_address(),
            payload,
        );

        let (_, _, _, received_coin) = self.receive_interchain_transfer_with_data<COIN>(
            approved_message,
            &channel,
            &clock,
            ctx,
        );

        clock.destroy_for_testing();
        channel.destroy();
        sui::test_utils::destroy(self);
        sui::test_utils::destroy(received_coin);
    }

    #[test]
    #[expected_failure(abort_code = EInterchainTransferHasNoData)]
    fun test_receive_interchain_transfer_with_data_no_data() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut self = create_for_testing(ctx);

        let coin_info =
            interchain_token_service::coin_info::from_info<COIN>(
        string::utf8(b"Name"),
        ascii::string(b"Symbol"),
        10,
    );

        let amount = 1234;
        let mut coin_management = interchain_token_service::coin_management::new_locked();
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        coin_management.take_balance(coin.into_balance(), &clock);

        let token_id = self.register_coin(coin_info, coin_management);
        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
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
        let mut payload = writer.into_bytes();
        writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB).write_bytes(source_chain.into_bytes()).write_bytes(payload);
        payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            message_id,
            ITS_HUB_ADDRESS.to_ascii_string(),
            self.channel.to_address(),
            payload,
        );

        let (_, _, _, received_coin) = self.receive_interchain_transfer_with_data<COIN>(
            approved_message,
            &channel,
            &clock,
            ctx,
        );

        clock.destroy_for_testing();
        channel.destroy();
        sui::test_utils::destroy(self);
        sui::test_utils::destroy(received_coin);
    }

    #[test]
    fun test_receive_deploy_interchain_token_with_distributor() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut self = create_for_testing(ctx);

        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let name = b"Token Name";
        let symbol = b"Symbol";
        let decimals = 9;
        let token_id: u256 = 1234;
        let distributor = @0x1;

        self.create_unregistered_coin(symbol, decimals, ctx);

        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id)
            .write_bytes(name)
            .write_bytes(symbol)
            .write_u256((decimals as u256))
            .write_bytes(distributor.to_bytes());
        let mut payload = writer.into_bytes();
        writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB).write_bytes(source_chain.into_bytes()).write_bytes(payload);
        payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            message_id,
            ITS_HUB_ADDRESS.to_ascii_string(),
            self.channel.to_address(),
            payload,
        );

        self.receive_deploy_interchain_token<COIN>(approved_message);

        clock.destroy_for_testing();
        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMessageType)]
    fun test_receive_deploy_interchain_token_invalid_message_type() {
        let ctx = &mut tx_context::dummy();
        let clock = sui::clock::create_for_testing(ctx);
        let mut self = create_for_testing(ctx);

        let source_chain = ascii::string(b"Chain Name");
        let message_id = ascii::string(b"Message Id");
        let name = b"Token Name";
        let symbol = b"Symbol";
        let decimals = 9;
        let token_id: u256 = 1234;

        self.create_unregistered_coin(symbol, decimals, ctx);

        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id)
            .write_bytes(name)
            .write_bytes(symbol)
            .write_u256((decimals as u256))
            .write_bytes(b"");
        let mut payload = writer.into_bytes();
        writer = abi::new_writer(3);
        writer.write_u256(MESSAGE_TYPE_RECEIVE_FROM_HUB).write_bytes(source_chain.into_bytes()).write_bytes(payload);
        payload = writer.into_bytes();

        let approved_message = channel::new_approved_message(
            ITS_HUB_CHAIN_NAME.to_ascii_string(),
            message_id,
            ITS_HUB_ADDRESS.to_ascii_string(),
            self.channel.to_address(),
            payload,
        );

        self.receive_deploy_interchain_token<COIN>(approved_message);

        clock.destroy_for_testing();
        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EUnregisteredCoinHasUrl)]
    fun test_give_unregistered_coin_with_url() {
        let name = b"Coin";
        let symbol = b"COIN";
        let decimals = 12;
        let ctx = &mut tx_context::dummy();
        let mut self = create_for_testing(ctx);
        let url = sui::url::new_unsafe_from_bytes(b"url");

        let (treasury_cap, coin_metadata) = interchain_token_service::coin::create_treasury_and_metadata_custom(
            name,
            symbol,
            decimals,
            option::some(url),
            ctx,
        );

        self.give_unregistered_coin<COIN>(treasury_cap, coin_metadata);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = ENotDistributor)]
    fun test_burn_as_distributor_not_distributor() {
        let ctx = &mut tx_context::dummy();
        let mut self = create_for_testing(ctx);
        let symbol = b"COIN";
        let decimals = 9;
        let amount = 1234;

        let (mut treasury_cap, coin_metadata) = interchain_token_service::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let coin = treasury_cap.mint(amount, ctx);
        let coin_info = interchain_token_service::coin_info::from_metadata<COIN>(
        coin_metadata,
    );
        let mut coin_management = interchain_token_service::coin_management::new_with_cap(treasury_cap);

        let channel = channel::new(ctx);
        coin_management.add_distributor(@0x1);

        let token_id = self.register_coin(coin_info, coin_management);
        self.burn_as_distributor<COIN>(&channel, token_id, coin);

        sui::test_utils::destroy(self);
        channel.destroy();
    }

    #[test]
    #[expected_failure(abort_code = ENonZeroTotalSupply)]
    fun test_give_unregistered_coin_not_zero_total_supply() {
        let symbol = b"COIN";
        let decimals = 12;
        let ctx = &mut tx_context::dummy();
        let mut self = create_for_testing(ctx);

        let (mut treasury_cap, coin_metadata) = interchain_token_service::coin::create_treasury_and_metadata(symbol, decimals, ctx);
        let coin = treasury_cap.mint(1, ctx);

        self.give_unregistered_coin<COIN>(treasury_cap, coin_metadata);

        sui::test_utils::destroy(self);
        sui::test_utils::destroy(coin);
    }

    #[test]
    #[expected_failure(abort_code = EModuleNameDoesNotMatchSymbol)]
    fun test_give_unregistered_coin_module_name_missmatch() {
        let symbol = b"SYMBOL";
        let decimals = 12;
        let ctx = &mut tx_context::dummy();
        let mut self = create_for_testing(ctx);

        let (treasury_cap, coin_metadata) = interchain_token_service::coin::create_treasury_and_metadata(
            symbol,
            decimals,
            ctx,
        );

        self.give_unregistered_coin<COIN>(treasury_cap, coin_metadata);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = ENotDistributor)]
    fun test_mint_as_distributor_not_distributor() {
        let ctx = &mut tx_context::dummy();
        let mut self = create_for_testing(ctx);
        let symbol = b"COIN";
        let decimals = 9;

        let (treasury_cap, coin_metadata) = interchain_token_service::coin::create_treasury_and_metadata(
            symbol,
            decimals,
            ctx,
        );
        let coin_info = interchain_token_service::coin_info::from_metadata<COIN>(
        coin_metadata,
    );
        let mut coin_management = interchain_token_service::coin_management::new_with_cap(treasury_cap);

        let channel = channel::new(ctx);
        coin_management.add_distributor(@0x1);
        let amount = 1234;

        let token_id = self.register_coin(coin_info, coin_management);
        let coin = self.mint_as_distributor<COIN>(
            &channel,
            token_id,
            amount,
            ctx,
        );

        assert!(coin.value() == amount);

        sui::test_utils::destroy(self);
        sui::test_utils::destroy(coin);
        channel.destroy();
    }

    #[test]
    #[expected_failure(abort_code = EUnregisteredCoin)]
    fun test_coin_data_not_registered() {
        let ctx = &mut tx_context::dummy();
        let self = create_for_testing(ctx);
        let token_id = token_id::from_address(@0x1);

        self.coin_data<COIN>(token_id);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = ENotDistributor)]
    fun test_mint_to_as_distributor_not_distributor() {
        let ctx = &mut tx_context::dummy();
        let mut its = create_for_testing(ctx);
        let symbol = b"COIN";
        let decimals = 9;

        let (treasury_cap, coin_metadata) = interchain_token_service::coin::create_treasury_and_metadata(
            symbol,
            decimals,
            ctx,
        );
        let coin_info = interchain_token_service::coin_info::from_metadata<COIN>(
        coin_metadata,
    );
        let mut coin_management = interchain_token_service::coin_management::new_with_cap(treasury_cap);

        let channel = channel::new(ctx);
        coin_management.add_distributor(@0x1);
        let amount = 1234;

        let token_id = register_coin(&mut its, coin_info, coin_management);
        mint_to_as_distributor<COIN>(
            &mut its,
            &channel,
            token_id,
            @0x2,
            amount,
            ctx,
        );

        sui::test_utils::destroy(its);
        channel.destroy();
    }

    #[test]
    #[expected_failure(abort_code = EOverflow)]
    fun test_read_amount_overflow() {
        let mut writer = abi::new_writer(1);
        writer.write_u256(1u256 << 64);

        let mut reader = abi::new_reader(writer.into_bytes());

        read_amount(&mut reader);
    }

    #[test]
    #[expected_failure(abort_code = EUnregisteredCoin)]
    fun test_registered_coin_type_not_registered() {
        let ctx = &mut tx_context::dummy();
        let its = create_for_testing(ctx);
        let token_id = token_id::from_address(@0x1);

        its.registered_coin_type(token_id);

        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = EUnregisteredCoin)]
    fun test_unregistered_coin_type_not_registered() {
        let ctx = &mut tx_context::dummy();
        let its = create_for_testing(ctx);
        let symbol = &b"symbol".to_ascii_string();
        let decimals = 8;

        its.unregistered_coin_type(symbol, decimals);

        sui::test_utils::destroy(its);
    }

    #[test]
    #[expected_failure(abort_code = ENewerTicket)]
    fun test_send_interchain_transfer_newer_ticket() {
        let ctx = &mut tx_context::dummy();
        let mut its = create_for_testing(ctx);

        let token_id = token_id::from_address(@0x1);
        let amount = 1234;
        let coin = sui::coin::mint_for_testing<COIN>(amount, ctx);
        let destination_chain = ascii::string(b"Chain Name");
        let destination_address = b"address";
        let metadata = b"";
        let source_channel = channel::new(ctx);
        let clock = sui::clock::create_for_testing(ctx);
        let current_version = 0;
        let invalid_version = 1;

        let interchain_transfer_ticket =
            interchain_token_service::interchain_transfer_ticket::new<COIN>(
        token_id,
        coin.into_balance(),
        source_channel.to_address(),
        destination_chain,
        destination_address,
        metadata,
        invalid_version,
    );
        let message_ticket = its.send_interchain_transfer<COIN>(
            interchain_transfer_ticket,
            current_version,
            &clock,
        );

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(source_channel);
        sui::test_utils::destroy(message_ticket);
        sui::test_utils::destroy(clock);
    }

    #[test]
    #[expected_failure(abort_code = EUntrustedChain)]
    fun test_prepare_hub_message_untrusted_chain() {
        let ctx = &mut tx_context::dummy();
        let its = create_for_testing(ctx);
        let payload = b"payload";
        let destination_chain = b"destination_chain".to_ascii_string();

        let message_ticket = its.prepare_hub_message(payload, destination_chain);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(message_ticket);
    }
}
