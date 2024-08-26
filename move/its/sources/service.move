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

    use governance::governance::{Self, Governance};

    use its::its::{ITS};
    use its::coin_info::{Self, CoinInfo};
    use its::token_id::{Self, TokenId};
    use its::coin_management::{Self, CoinManagement};
    use its::utils as its_utils;

    use axelar_gateway::gateway;
    use axelar_gateway::channel::Channel;

    const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
    const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
    //const MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;
    const MESSAGE_TYPE_SEND_TO_HUB: u256 = 3;
    const MESSAGE_TYPE_RECEIVE_FROM_HUB: u256 = 4;

    /**
     * @dev Chain name for Axelar. This is used for routing ITS calls via ITS hub on Axelar.
     */
    const ITS_HUB_CHAIN_NAME: vector<u8> = b"Axelarnet";

    /**
     * @dev Identifier to be used as destination address for chains that route to hub. For Sui this will probably be every supported chain.
     */
    const ITS_HUB_ROUTING_IDENTIFIER: vector<u8> = b"hub";

    // address::to_u256(address::from_bytes(keccak256(b"sui-set-trusted-addresses")));
    const MESSAGE_TYPE_SET_TRUSTED_ADDRESSES: u256 = 0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68;

    const DECIMALS_CAP: u8 = 9;

    const EUntrustedAddress: u64 = 0;
    const EInvalidMessageType: u64 = 1;
    const EWrongDestination: u64 = 2;
    const EInterchainTransferHasData: u64 = 3;
    const EInterchainTransferHasNoData: u64 = 4;
    const EModuleNameDoesNotMatchSymbol: u64 = 5;
    const ENotDistributor: u64 = 6;
    const ENonZeroTotalSupply: u64 = 7;
    const EUnregisteredCoinHasUrl: u64 = 8;
    const EMalformedTrustedAddresses: u64 = 9;
    const ESenderNotHub: u64 = 10;
    const EUntrustedChain: u64 = 11;

    public struct CoinRegistered<phantom T> has copy, drop {
        token_id: TokenId,
    }

    public fun register_coin<T>(
        self: &mut ITS, coin_info: CoinInfo<T>, coin_management: CoinManagement<T>
    ) {
        let token_id = token_id::from_coin_data(&coin_info, &coin_management);

        self.add_registered_coin(token_id, coin_management, coin_info);

        event::emit(CoinRegistered<T> {
            token_id
        })
    }

    public fun deploy_remote_interchain_token<T>(
        self: &mut ITS, token_id: TokenId, destination_chain: String
    ) {
        let coin_info = self.get_coin_info<T>(token_id);
        let name = coin_info.name();
        let symbol = coin_info.symbol();
        let decimals = coin_info.decimals();
        let mut writer = abi::new_writer(6);

        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(token_id.to_u256())
            .write_bytes(*string::bytes(&name))
            .write_bytes(*ascii::as_bytes(&symbol))
            .write_u256((decimals as u256))
            .write_bytes(vector::empty());

        send_payload(self, destination_chain, writer.into_bytes());
    }

    public fun interchain_transfer<T>(
        self: &mut ITS,
        token_id: TokenId,
        coin: Coin<T>,
        destination_chain: String,
        destination_address: vector<u8>,
        metadata: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let amount = self.coin_management_mut(token_id)
            .take_coin(coin, clock);
        let (_version, data) = its_utils::decode_metadata(metadata);
        let mut writer = abi::new_writer(6);

        writer
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(token_id.to_u256())
            .write_bytes(ctx.sender().to_bytes())
            .write_bytes(destination_address)
            .write_u256(amount)
            .write_bytes(data);

        send_payload(self, destination_chain, writer.into_bytes());
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
        let distributor = address::from_bytes(reader.read_bytes());
        let decimals = if (remote_decimals > DECIMALS_CAP) DECIMALS_CAP else remote_decimals;

        let (treasury_cap, mut coin_metadata) = self.remove_unregistered_coin<T>(
            token_id::unregistered_token_id(&symbol, decimals)
        );

        treasury_cap.update_name(&mut coin_metadata, name);
        //coin::update_symbol(&treasury_cap, &mut coin_metadata, symbol);

        let mut coin_management = coin_management::new_with_cap<T>(treasury_cap);
        let coin_info = coin_info::from_metadata<T>(coin_metadata, remote_decimals);

        coin_management.add_distributor(distributor);

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
        to: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = channel.to_address();

        assert!(coin_management.is_distributor(distributor), ENotDistributor);

        let coin = coin_management.mint(amount, ctx);
        transfer::public_transfer(coin, to)
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

        let mut trusted_address_info = bcs::new(reader.read_bytes());

        let mut chain_names = trusted_address_info.peel_vec_vec_u8();
        let mut trusted_addresses = trusted_address_info.peel_vec_vec_u8();

        let length = chain_names.length();

        assert!(length == trusted_addresses.length(), EMalformedTrustedAddresses);

        let mut i = 0;
        while(i < length) {
            its.set_trusted_address(
                ascii::string(chain_names.pop_back()),
                ascii::string(trusted_addresses.pop_back()),
            );
            i = i + 1;
        }
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
            assert!(source_chain.into_bytes() == ITS_HUB_CHAIN_NAME, ESenderNotHub);
            source_chain = ascii::string(reader.read_bytes());
            payload = reader.read_bytes();
        };

        (source_chain, payload)
    }

    /// Send a payload to a destination chain. The destination chain needs to have a trusted address.
    fun send_payload(self: &mut ITS, mut destination_chain: String, mut payload: vector<u8>) {
        let mut destination_address = self.get_trusted_address(destination_chain);

        // Prevent sending directly to the ITS Hub chain. This is not supported yet, so fail early to prevent the user from having their funds stuck.
        assert!(destination_chain.into_bytes() != ITS_HUB_CHAIN_NAME, EUntrustedChain);

        // Check whether the ITS call should be routed via ITS hub for this destination chain
        if(destination_address.into_bytes() == ITS_HUB_ROUTING_IDENTIFIER) {
            let mut writter = abi::new_writer(3);
            writter.write_u256(MESSAGE_TYPE_SEND_TO_HUB);
            writter.write_bytes(destination_chain.into_bytes());
            writter.write_bytes(payload);
            payload = writter.into_bytes();
            destination_chain = ascii::string(ITS_HUB_CHAIN_NAME);
            destination_address = self.get_trusted_address(destination_chain);
        };

        // Check whether no trusted address was set for the destination chain
        assert!(destination_address.length() > 0, EUntrustedChain);

        gateway::call_contract(self.channel_mut(), destination_chain, destination_address, payload);
    }
}
