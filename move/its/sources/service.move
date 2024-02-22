module its::service {
    use std::string;
    use std::ascii::{Self, String};
    use std::vector;
    use std::type_name;

    use sui::tx_context::TxContext;
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::transfer;
    use sui::address;
    use sui::event;
    use sui::bcs;

    use axelar::utils;
    use axelar::channel::{Self, ApprovedCall};

    use governance::governance::{Self, Governance};

    use its::its::{Self, ITS};
    use its::coin_info::{Self, CoinInfo};
    use its::token_id::{Self, TokenId};
    use its::coin_management::{Self, CoinManagement};
    use its::utils as its_utils;
    use its::token_channel::TokenChannel;

    use axelar::gateway;

    const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
    const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
    //const MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;
    
    // address::to_u256(address::from_bytes(keccak256(b"sui-set-trusted-addresses")));
    const MESSAGE_TYPE_SET_TRUSTED_ADDRESSES: u256 = 0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68;
    
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
        let mut payload = utils::abi_encode_start(6);

        utils::abi_encode_fixed(&mut payload, 0, MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN);
        utils::abi_encode_fixed(&mut payload, 1, token_id.to_u256());
        utils::abi_encode_variable(&mut payload, 2, *string::bytes(&name));
        utils::abi_encode_variable(&mut payload, 3, *ascii::as_bytes(&symbol));
        utils::abi_encode_fixed(&mut payload, 4, (decimals as u256));
        utils::abi_encode_variable(&mut payload, 5, vector::empty());

        send_payload(self, destination_chain, payload);
    }

    public fun interchain_transfer<T>(
        self: &mut ITS,
        token_id: TokenId,
        coin: Coin<T>,
        destination_chain: String,
        destination_address: vector<u8>,
        metadata: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let amount = (coin::value<T>(&coin) as u256);
        let (_version, data) = its_utils::decode_metadata(metadata);
        let mut payload = utils::abi_encode_start(6);

        utils::abi_encode_fixed(&mut payload, 0, MESSAGE_TYPE_INTERCHAIN_TRANSFER);
        utils::abi_encode_fixed(&mut payload, 1, token_id.to_u256());
        utils::abi_encode_variable(&mut payload, 2, address::to_bytes(ctx.sender()));
        utils::abi_encode_variable(&mut payload, 3, destination_address);
        utils::abi_encode_fixed(&mut payload, 4, amount);
        utils::abi_encode_variable(&mut payload, 5, data);

        self.coin_management_mut(token_id)
            .take_coin(coin);

        send_payload(self, destination_chain, payload);
    }

    public fun receive_interchain_transfer<T>(self: &mut ITS, approved_call: ApprovedCall, ctx: &mut TxContext) {
        let (_, payload) = decode_approved_call(self, approved_call);

        assert!(utils::abi_decode_fixed(&payload, 0) == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);
        assert!(vector::is_empty(&utils::abi_decode_variable(&payload, 5)), EInterchainTransferHasData);

        let token_id = token_id::from_u256(utils::abi_decode_fixed(&payload, 1));
        let destination_address = address::from_bytes(utils::abi_decode_variable(&payload, 3));
        let amount = (utils::abi_decode_fixed(&payload, 4) as u64);

        let coin = self
            .coin_management_mut(token_id)
            .give_coin<T>(amount, ctx);

        transfer::public_transfer(coin, destination_address)
    }

    public fun receive_interchain_transfer_with_data<T>(
        self: &mut ITS,
        approved_call: ApprovedCall,
        token_channel: &TokenChannel,
        ctx: &mut TxContext
    ): (String, vector<u8>, vector<u8>, Coin<T>) {
        let (source_chain, payload) = decode_approved_call(self, approved_call);

        assert!(utils::abi_decode_fixed(&payload, 0) == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);
        assert!(address::from_bytes(utils::abi_decode_variable(&payload, 3)) == token_channel.to_address(), EWrongDestination);

        let token_id = token_id::from_u256(utils::abi_decode_fixed(&payload, 1));
        let source_address = utils::abi_decode_variable(&payload, 2);
        let amount = (utils::abi_decode_fixed(&payload, 4) as u64);
        let data = utils::abi_decode_variable(&payload, 5);

        assert!(!vector::is_empty(&data), EInterchainTransferHasNoData);

        let coin = self
            .coin_management_mut(token_id)
            .give_coin(amount, ctx);

        (
            source_chain,
            source_address,
            data,
            coin,
        )
    }

    public fun receive_deploy_interchain_token<T>(self: &mut ITS, approved_call: ApprovedCall) {
        let (_, payload) = decode_approved_call(self, approved_call);

        assert!(utils::abi_decode_fixed(&payload, 0) == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);

        let token_id = token_id::from_u256(utils::abi_decode_fixed(&payload, 1));
        let name = string::utf8(utils::abi_decode_variable(&payload, 2));
        let symbol = ascii::string(utils::abi_decode_variable(&payload, 3));
        let decimals = (utils::abi_decode_fixed(&payload, 4) as u8);
        let distributor = address::from_bytes(utils::abi_decode_variable(&payload, 5));

        let (treasury_cap, mut coin_metadata) = self.remove_unregistered_coin<T>(
            token_id::unregistered_token_id(&symbol, decimals)
        );

        treasury_cap.update_name(&mut coin_metadata, name);
        //coin::update_symbol(&treasury_cap, &mut coin_metadata, symbol);

        let mut coin_management = coin_management::new_with_cap<T>(treasury_cap);
        let coin_info = coin_info::from_metadata<T>(coin_metadata);

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
        token_channel: &TokenChannel,
        token_id: TokenId,
        to: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = token_channel.to_address();

        assert!(coin_management.is_distributor(distributor), ENotDistributor);

        let coin = coin_management.give_coin(amount, ctx);
        transfer::public_transfer(coin, to)
    }

    public fun burn_as_distributor<T>(
        self: &mut ITS,
        token_channel: &TokenChannel,
        token_id: TokenId,
        coin: Coin<T>
    ) {
        let coin_management = self.coin_management_mut<T>(token_id);
        let distributor = token_channel.to_address();

        assert!(coin_management.is_distributor<T>(distributor), ENotDistributor);

        coin_management.take_coin(coin);
    }

    // === Special Call Receiving
    public fun set_trusted_addresses(self: &mut ITS, governance: &Governance, approved_call: ApprovedCall) {
        let (source_chain, source_address, payload) = channel::consume_approved_call(
            its::channel_mut(self), approved_call
        );

        assert!(governance::is_governance(governance, source_chain, source_address), EUntrustedAddress);

        let message_type = utils::abi_decode_fixed(&payload, 0);
        assert!(message_type == MESSAGE_TYPE_SET_TRUSTED_ADDRESSES, EInvalidMessageType);

        let mut trusted_address_info = bcs::new(utils::abi_decode_variable(&payload, 1));

        let mut chain_names = bcs::peel_vec_vec_u8(&mut trusted_address_info);
        let mut trusted_addresses = bcs::peel_vec_vec_u8(&mut trusted_address_info);

        let length = vector::length(&chain_names);

        assert!(length == vector::length(&trusted_addresses), EMalformedTrustedAddresses);

        let mut i = 0;
        while(i < length) {
            its::set_trusted_address(
                self,
                ascii::string(vector::pop_back(&mut chain_names)),
                ascii::string(vector::pop_back(&mut trusted_addresses)),
            );
            i = i + 1;
        }
    }

    // === Internal functions ===

    /// Decode an approved call and check that the source chain is trusted.
    fun decode_approved_call(self: &mut ITS, approved_call: ApprovedCall): (String, vector<u8>) {
        let (
            source_chain,
            source_address,
            payload
        ) = self.channel_mut().consume_approved_call(approved_call);

        assert!(self.is_trusted_address(source_chain, source_address), EUntrustedAddress);

        (source_chain, payload)
    }

    /// Send a payload to a destination chain. The destination chain needs to have a trusted address.
    fun send_payload(self: &mut ITS, destination_chain: String, payload: vector<u8>) {
        let destination_address = self.get_trusted_address(destination_chain);
        gateway::call_contract(self.channel_mut(), destination_chain, destination_address, payload);
    }
}
