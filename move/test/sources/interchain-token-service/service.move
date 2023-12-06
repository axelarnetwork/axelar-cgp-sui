module interchain_token_service::service {
    use std::string;
    use std::ascii::{Self, String};
    use std::vector;
    use std::option;
    use std::type_name;

    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::address;

    use axelar::utils;
    use axelar::channel::{Self, ApprovedCall};

    use interchain_token_service::storage::{Self, ITS};
    use interchain_token_service::coin_info::{Self, CoinInfo};
    use interchain_token_service::token_id::{Self, TokenId};
    use interchain_token_service::coin_management::{Self, CoinManagement};
    use interchain_token_service::its_utils;
    use interchain_token_service::interchain_token_channel::{Self, TokenChannel};

    use axelar::gateway;

    const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
    const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
    //const MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;

    const EUntrustedAddress: u64 = 0;
    const EInvalidMessageType: u64 = 1;
    const EWrongDestination: u64 = 2;
    const EInterchainTransferHasData: u64 = 3;
    const EInterchainTransferHasNoData: u64 = 4;
    const EModuleNameDoesNotMatchSymbol: u64 = 5;
    const ENotDistributor: u64 = 6;
    const ENonZeroTotalSupply: u64 = 7;
    const EUnregisteredCoinHasUrl: u64 = 8;

    public fun register_coin<T>(self: &mut ITS, coin_info: CoinInfo<T>, coin_management: CoinManagement<T>) {
        let token_id = token_id::from_coin_info(&coin_info);

        storage::add_registered_coin(self, token_id, coin_management, coin_info);
    }

    public fun deploy_remote_interchain_token<T>(self: &mut ITS, token_id: TokenId, destination_chain: String) {
        let coin_info = storage::borrow_coin_info<T>(self, token_id);
        let name = coin_info::name(coin_info);
        let symbol = coin_info::symbol(coin_info);
        let decimals = coin_info::decimals(coin_info);
        let payload = utils::abi_encode_start(6);
        utils::abi_encode_fixed(&mut payload, 0, MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN);
        utils::abi_encode_fixed(&mut payload, 1, token_id::to_u256(&token_id));
        utils::abi_encode_variable(&mut payload, 2, *string::bytes(&name));
        utils::abi_encode_variable(&mut payload, 3, *ascii::as_bytes(&symbol));
        utils::abi_encode_fixed(&mut payload, 4,(decimals as u256));
        utils::abi_encode_variable(&mut payload, 5, vector::empty<u8>());

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

        let payload = utils::abi_encode_start(6);
        utils::abi_encode_fixed(&mut payload, 0, MESSAGE_TYPE_INTERCHAIN_TRANSFER);
        utils::abi_encode_fixed(&mut payload, 1, token_id::to_u256(&token_id));
        utils::abi_encode_variable(&mut payload, 2, address::to_bytes(tx_context::sender(ctx)));
        utils::abi_encode_variable(&mut payload, 3, destination_address);
        utils::abi_encode_fixed(&mut payload, 4, amount);
        utils::abi_encode_variable(&mut payload, 5, data);

        coin_management::take_coin<T>(storage::borrow_mut_coin_management(self, token_id), coin);

        send_payload(self, destination_chain, payload);
    }

    public fun receive_interchain_transfer<T>(self: &mut ITS, approved_call: ApprovedCall, ctx: &mut TxContext) {
        let (_, payload) = decode_approved_call(self, approved_call);

        assert!(utils::abi_decode_fixed(&payload, 0) == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);
        assert!(vector::is_empty(&utils::abi_decode_variable(&payload, 5)), EInterchainTransferHasData);
        let token_id = token_id::from_u256(utils::abi_decode_fixed(&payload, 1));
        let destination_address = address::from_bytes(utils::abi_decode_variable(&payload, 3));
        let amount = (utils::abi_decode_fixed(&payload, 4) as u64);

        coin_management::give_coin_to<T>(storage::borrow_mut_coin_management(self, token_id), destination_address, amount, ctx);
    }

    public fun receive_interchain_transfer_with_data<T>(self: &mut ITS, approved_call: ApprovedCall, token_channel: &TokenChannel, ctx: &mut TxContext): (String, vector<u8>, vector<u8>, Coin<T>) {
        let (source_chain, payload) = decode_approved_call(self, approved_call);

        assert!(utils::abi_decode_fixed(&payload, 0) == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);
        assert!(address::from_bytes(utils::abi_decode_variable(&payload, 3)) == interchain_token_channel::to_address(token_channel), EWrongDestination);
        let token_id = token_id::from_u256(utils::abi_decode_fixed(&payload, 1));
        let source_address = utils::abi_decode_variable(&payload, 2);
        let amount = (utils::abi_decode_fixed(&payload, 4) as u64);
        let data = utils::abi_decode_variable(&payload, 5);

        assert!(!vector::is_empty(&data), EInterchainTransferHasNoData);

        (source_chain, source_address, data, coin_management::give_coin<T>(storage::borrow_mut_coin_management(self, token_id), amount, ctx))
    }

    public fun receive_deploy_interchain_token<T>(self: &mut ITS, approved_call: ApprovedCall) {
        let (_, payload) = decode_approved_call(self, approved_call);

        assert!(utils::abi_decode_fixed(&payload, 0) == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);
        let token_id = token_id::from_u256(utils::abi_decode_fixed(&payload, 1));
        let name = string::utf8(utils::abi_decode_variable(&payload, 2));
        let symbol = ascii::string(utils::abi_decode_variable(&payload, 3));
        let decimals =(utils::abi_decode_fixed(&payload, 4) as u8);
        let distributor = address::from_bytes(utils::abi_decode_variable(&payload, 5));
        
        let (treasury_cap, coin_metadata) = storage::remove_unregistered_coin<T>(self, token_id::unregistered_token_id(&symbol, &decimals));

        coin::update_name(&treasury_cap, &mut coin_metadata, name);
        coin::update_symbol(&treasury_cap, &mut coin_metadata, symbol);
        
        let coin_management = coin_management::mint_burn<T>(treasury_cap);
        let coin_info = coin_info::from_metadata<T>(coin_metadata);

        coin_management::add_distributor(&mut coin_management, distributor);

        storage::add_registered_coin<T>(self, token_id, coin_management, coin_info);
    }

    // We need an empty coin that has the proper decimals and typing, and no Url.
    public fun give_unregistered_coin<T>(self: &mut ITS, treasury_cap: TreasuryCap<T>, coin_metadata: CoinMetadata<T>) {
        assert!(coin::total_supply(&treasury_cap) == 0, ENonZeroTotalSupply);
        assert!(option::is_none(&coin::get_icon_url(&coin_metadata)), EUnregisteredCoinHasUrl);

        coin::update_description(&treasury_cap, &mut coin_metadata, string::utf8(b""));

        let decimals = coin::get_decimals(&coin_metadata);
        let symbol = coin::get_symbol(&coin_metadata);

        let module_name = type_name::get_module(&type_name::get<T>());
        assert!(&module_name == &its_utils::get_module_from_symbol(&symbol), EModuleNameDoesNotMatchSymbol);
        
        let token_id = token_id::unregistered_token_id(&symbol, &decimals);
        
        storage::add_unregistered_coin<T>(self, token_id, treasury_cap, coin_metadata);
    }

    fun decode_approved_call(self: &mut ITS, approved_call: ApprovedCall): (String, vector<u8>) {
        let (source_chain, source_address, payload) = channel::consume_approved_call(storage::borrow_mut_channel(self), approved_call);

        assert!(storage::is_trusted_address(self, source_chain, source_address), EUntrustedAddress);

        (source_chain, payload)
    }
    fun send_payload(self: &mut ITS, destination_chain: String, payload: vector<u8>) {
        let destination_address = storage::get_trusted_address(self, destination_chain);
        gateway::call_contract(storage::borrow_mut_channel(self), destination_chain, destination_address, payload);
    }

    public fun mint_as_distributor<T>(self: &mut ITS, token_channel: &TokenChannel, token_id: TokenId, to: address, amount: u64, ctx: &mut TxContext) {
        let coin_management = storage::borrow_mut_coin_management<T>(self, token_id);
        assert!(coin_management::is_distributor<T>(coin_management, interchain_token_channel::to_address(token_channel)), ENotDistributor);

        coin_management::give_coin_to(coin_management, to, amount, ctx);
    } 

    public fun burn_as_distributor<T>(self: &mut ITS, token_channel: &TokenChannel, token_id: TokenId, coin: Coin<T>) {
        let coin_management = storage::borrow_mut_coin_management<T>(self, token_id);
        assert!(coin_management::is_distributor<T>(coin_management, interchain_token_channel::to_address(token_channel)), ENotDistributor);

        coin_management::take_coin(coin_management, coin);
    } 
} 