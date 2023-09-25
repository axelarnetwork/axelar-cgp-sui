module dummy_its::its {
  use std::string::{String};
  use std::ascii::{Self};
  use std::option;
  use std::type_name;
  use std::string;
  use std::vector;

  use sui::object::{Self, UID};
  use sui::address::{Self};
  use sui::transfer;  
  use sui::tx_context::{TxContext};
  use sui::coin::{Self, TreasuryCap, CoinMetadata, Coin};
  use sui::dynamic_field as df;
  use sui::url::{Url};

  use axelar::utils::{Self};
  use axelar::channel::{Self, Channel, ApprovedCall};

  use dummy_its::its_utils::{convert_value, get_module_from_symbol, hash_coin_info};

  const SELECTOR_SEND_TOKEN: u256 = 1;
  const SELECTOR_SEND_TOKEN_WITH_DATA: u256 = 2;
  const SELECTOR_DEPLOY_TOKEN_MANAGER: u256 = 3;
  const SELECTOR_DEPLOY_AND_REGISTER_STANDARDIZED_TOKEN: u256 = 4;

  const EUntrustedAddress: u64 = 0;
  const EDecimalsMissmatch: u64 = 1;
  const EIconUrlExists: u64 = 2;
  const EWrongSelector: u64 = 3;
  const EWrongDestination: u64 = 4;
  const EValueMissmatch: u64 = 5;
  const EWrongModuleName: u64 = 6;

  struct CoinData<phantom T> has store {
    cap: TreasuryCap<T>,
    metadata: CoinMetadata<T>,
  }

  struct CoinChannel has store {
    id: UID,
  }

  struct ChannelType has key {
    id: UID,
    get_call_object_ids: vector<address>,
  }

  struct ChannelWitness has drop {}

  struct ITS has key {
      id: UID,
      channel: Channel<ChannelType>,
      trusted_address: String,
      registered_coins: UID,
      registered_coin_types: UID,
      unregistered_coins: UID,
      unregistered_coin_types: UID,
  }

  fun init(ctx: &mut TxContext) {
    let (its, channel_type) = get_singleton_its(ctx);
    transfer::share_object(its);
    transfer::share_object(channel_type);
  }

  fun get_singleton_its(ctx: &mut TxContext) : (ITS, ChannelType) {
    let id = object::new(ctx);
    let channel_type = ChannelType {
      id:  object::new(ctx),
      get_call_object_ids: vector::singleton(object::uid_to_address(&id)),
    };
    let its = ITS {
      id,
      channel: channel::create_channel<ChannelType, ChannelWitness>(&channel_type, ChannelWitness {} , ctx),
      trusted_address: string::utf8(x"00"),
      registered_coins: object::new(ctx),
      registered_coin_types: object::new(ctx),
      unregistered_coins: object::new(ctx),
      unregistered_coin_types: object::new(ctx),
    };
    (its, channel_type)
  }

  public fun create_coin_channel(ctx: &mut TxContext): CoinChannel {
    CoinChannel {
        id: object::new(ctx),
    }
  }

  public fun get_unregistered_coin_type(its: &ITS, symbol: &ascii::String, decimals: &u8): ascii::String {
    *df::borrow<address, ascii::String>(&its.unregistered_coin_types, hash_coin_info(symbol, decimals))
  }

  public fun get_registered_coin_type(its: &ITS, tokenId: address): ascii::String {
    *df::borrow<address, ascii::String>(&its.unregistered_coin_types, tokenId)
  }

  public fun registerCoin<T>(approved_call: ApprovedCall, its: &mut ITS) {
    //let data: &mut Empty;
    //let source_chain: String;
    let source_address: String;
    let payload: vector<u8>;
    (
        _,
        source_address,
        payload,
    ) = channel::consume_approved_call<ChannelType>(
        &mut its.channel,
        approved_call,
    );
    assert!(&source_address == &its.trusted_address, EUntrustedAddress);
    let selector = utils::abi_decode_fixed(&payload, 0);

    assert!(selector == SELECTOR_DEPLOY_AND_REGISTER_STANDARDIZED_TOKEN, EWrongSelector);
    let tokenId = address::from_u256(utils::abi_decode_fixed(&payload, 1));

    let decimals = (utils::abi_decode_fixed(&payload, 4) as u8);
    let symbol = ascii::string(utils::abi_decode_variable(&payload, 3));
    let coin_info_hash = hash_coin_info(&symbol, &decimals);
    let coin_data = df::remove<address, CoinData<T>>(&mut its.unregistered_coins, coin_info_hash);


    let name = string::utf8(utils::abi_decode_variable(&payload, 2));
    coin::update_name<T>(&coin_data.cap, &mut coin_data.metadata, name);
    coin::update_description<T>(&coin_data.cap, &mut coin_data.metadata, string::utf8(b""));
      
    df::add(&mut its.registered_coins, tokenId, coin_data);

    let coin_type = df::remove<address, ascii::String>(&mut its.unregistered_coin_types, coin_info_hash);
    df::add(&mut its.registered_coin_types, tokenId, coin_type);
  }

  public fun receive_coin<T>(approved_call: ApprovedCall, its: &mut ITS, ctx: &mut TxContext) {
    //let data: &mut Empty;
    //let source_chain: String;
    let source_address: String;
    let payload: vector<u8>;
    (
        _,
        source_address,
        payload,
    ) = channel::consume_approved_call<ChannelType>(
        &mut its.channel,
        approved_call,
    );
    assert!(&source_address == &its.trusted_address, EUntrustedAddress);
    let selector = utils::abi_decode_fixed(&payload, 0);
    
    assert!(selector == SELECTOR_SEND_TOKEN, EWrongSelector);
    let tokenId = address::from_u256(utils::abi_decode_fixed(&payload, 1));
      
    let cap = &mut df::borrow_mut<address, CoinData<T>>(&mut its.registered_coins, tokenId).cap;
    let destination_address = address::from_bytes(utils::abi_decode_variable(&payload, 2));
    let value = convert_value(utils::abi_decode_fixed(&payload, 3));
    coin::mint_and_transfer<T>(cap, value, destination_address, ctx);
  }

  public fun receive_coin_with_data<T>(approved_call: ApprovedCall, its: &mut ITS, channel: &CoinChannel, ctx: &mut TxContext): (Coin<T>, String, vector<u8>, vector<u8>) {
    //let data: &mut Empty;
    let source_chain: String;
    let source_address: String;
    let payload: vector<u8>;
    (
        source_chain,
        source_address,
        payload,
    ) = channel::consume_approved_call<ChannelType>(
        &mut its.channel,
        approved_call,
    );
    assert!(&source_address == &its.trusted_address, EUntrustedAddress);
    let selector = utils::abi_decode_fixed(&payload, 0);
    
    assert!(selector == SELECTOR_SEND_TOKEN, EWrongSelector);
    let tokenId = address::from_u256(utils::abi_decode_fixed(&payload, 1));
      
    let cap = df::borrow_mut<address, TreasuryCap<T>>(&mut its.registered_coins, tokenId);
    let destination_address = address::from_u256(utils::abi_decode_fixed(&payload, 2));

    assert!(object::uid_to_address(&channel.id) == destination_address, EWrongDestination);

    let value = convert_value(utils::abi_decode_fixed(&payload, 3));
    let coin_source_address = utils::abi_decode_variable(&payload, 4);
    let data = utils::abi_decode_variable(&payload, 5);
    let coin = coin::mint<T>(cap, value, ctx);
    (
      coin,
      source_chain,
      coin_source_address,
      data,
    )
  }

  public fun give_coin_info<T>(its: &mut ITS, cap: TreasuryCap<T>, metadata: CoinMetadata<T>, symbol: ascii::String, decimals: u8) {
    let type_name = type_name::get_module(&type_name::get<T>());
    
    assert!(option::is_none<Url>(&coin::get_icon_url<T>(&metadata)), EIconUrlExists);
    assert!(&get_module_from_symbol(&symbol) == &type_name, EWrongModuleName);
    assert!(decimals == coin::get_decimals<T>(&metadata), EDecimalsMissmatch);

    coin::update_symbol<T>(&cap, &mut metadata, symbol);

    let id = hash_coin_info(&symbol, &decimals);
    df::add(&mut its.unregistered_coins, id, CoinData {
      cap,
      metadata
    });

    df::add(&mut its.unregistered_coin_types, id, type_name);
  }

  public fun get_call_info(payload: &vector<u8>, its: &ITS): vector<u8> {
    let selector = utils::abi_decode_fixed(payload, 0);
    if(selector == SELECTOR_DEPLOY_AND_REGISTER_STANDARDIZED_TOKEN) {
        let symbol = ascii::string(utils::abi_decode_variable(payload, 3));
        let decimals = (utils::abi_decode_fixed(payload, 4) as u8);
        let coin_type = get_unregistered_coin_type(its, &symbol, &decimals);
        let v = b"{\"target\":\"0x";
        vector::append(&mut v, *ascii::as_bytes(&type_name::get_address(&type_name::get<ITS>())));
        vector::append(&mut v, b"::its::registerCoin\",\"arguments\":[\"contractCall\",\"obj:");
        vector::append(&mut v, *ascii::as_bytes(&address::to_ascii_string(object::id_address(its))));
        vector::append(&mut v, b"\"],\"typeArguments\":[\"");
        vector::append(&mut v, *ascii::as_bytes(&coin_type));
        vector::append(&mut v, b"\"]}");
        return v
    } else if (selector == SELECTOR_SEND_TOKEN) {
        let v = b"{\"target\":\"";
        return v
    } else if (selector == SELECTOR_SEND_TOKEN_WITH_DATA) {
        let v = b"{\"target\":\"";
        return v
    };
    b""
  }


  #[test_only]
  use sui::test_scenario::{Self as ts, ctx, Scenario};
  #[test_only]
  use sui::bcs::{Self};
  #[test_only]
  const TEST_SENDER_ADDR: address = @0xA11CE;
  #[test_only]
  use axelar::utils::operators_hash;
  #[test_only]
  use sui::vec_map;
  #[test_only]
  const TOKEN_ID: u256 = (123 as u256);

  #[test_only]
  fun get_approved_call(test: &mut Scenario, its: &ITS, payload: vector<u8>): ApprovedCall {
    use sui::hash::{Self};
    use axelar::validators;
    use axelar::gateway;

    let source_chain: String = string::utf8(b"Ethereum");

    // public keys of `operators`
    let epoch = 1;
    let operators = vector[
        x"037286a4f1177bea06c8e15cf6ec3df0b7747a01ac2329ca2999dfd74eff599028"
    ];

    let epoch_for_hash = vec_map::empty();
    vec_map::insert(&mut epoch_for_hash, operators_hash(&operators, &vector[100u128], 10u128), epoch);

    ts::next_tx(test, @0x0);
    let temp = object::new(ctx(test));
    let command_id : address = object::uid_to_address(&temp);
    object::delete(temp);
    // create validators for testing
    let validators = validators::new(
        epoch,
        epoch_for_hash,
        ctx(test)
    );

    let channelId = bcs::peel_address(&mut bcs::new(channel::source_id(&its.channel)));
    validators::add_approval_for_testing(
      &mut validators, 
      command_id,
      source_chain,
      its.trusted_address,
      channelId,
      hash::keccak256(&payload),
    );

    let call = gateway::take_approved_call(
      &mut validators,
      command_id,
      source_chain,
      its.trusted_address,
      channelId,
      payload,
    );
    validators::drop_for_test(validators);

    call
  }

  #[test_only]
  fun register_coin(test: &mut Scenario, its: &mut ITS) {
    use dummy_its::coin_registry::{Self, COIN_REGISTRY};
    
    let payload = utils::abi_encode_start(9);
    utils::abi_encode_fixed(&mut payload, 0, SELECTOR_DEPLOY_AND_REGISTER_STANDARDIZED_TOKEN);
    utils::abi_encode_fixed(&mut payload, 1, TOKEN_ID);
    utils::abi_encode_variable(&mut payload, 2, b"Token Name");
    utils::abi_encode_variable(&mut payload, 3, b"COIN_REGISTRY");
    utils::abi_encode_fixed(&mut payload, 4, 18);
    utils::abi_encode_variable(&mut payload, 5, x"00");
    utils::abi_encode_variable(&mut payload, 6, x"03");
    utils::abi_encode_fixed(&mut payload, 7, 12345);
    utils::abi_encode_variable(&mut payload, 8, x"00");

    let call = get_approved_call(test, its, payload);

    ts::next_tx(test, @0x0);
    coin_registry::init_for_testing(ctx(test));

    ts::next_tx(test, @0x0);
    let treasuryCap = ts::take_from_sender<TreasuryCap<COIN_REGISTRY>>(test);
    let coinMetadata = ts::take_from_sender<CoinMetadata<COIN_REGISTRY>>(test);
    give_coin_info<COIN_REGISTRY>(its, treasuryCap, coinMetadata, ascii::string(b"COIN_REGISTRY"), 18);

    registerCoin<COIN_REGISTRY>(call, its);
  }
  #[test]
  fun test_register_coin() {   
    use sui::test_scenario::{Self as ts, ctx};
    use sui::test_utils::{Self as tu};

    let test = ts::begin(@0x0);
    let (its, channel_type) = get_singleton_its(ctx(&mut test));

    register_coin(&mut test, &mut its);

    tu::destroy(its);
    tu::destroy(channel_type);
    ts::end(test);
  }

  #[test]
  fun test_receive_coin() {   
    use sui::test_scenario::{Self as ts, ctx};
    use sui::test_utils::{Self as tu};
    use dummy_its::coin_registry::{COIN_REGISTRY};

    let test = ts::begin(@0x0);
    let (its, channel_type) = get_singleton_its(ctx(&mut test));

    register_coin(&mut test, &mut its);

    let receiver = @0x76;
    let amount = 1234;

    let payload = utils::abi_encode_start(4);
    utils::abi_encode_fixed(&mut payload, 0, SELECTOR_SEND_TOKEN);
    utils::abi_encode_fixed(&mut payload, 1, TOKEN_ID);
    utils::abi_encode_variable(&mut payload, 2, address::to_bytes(receiver));
    utils::abi_encode_fixed(&mut payload, 3, amount);

    let call = get_approved_call(
      &mut test,
      &its,
      payload,
    );

    ts::next_tx(&mut test, @0x0);
    receive_coin<COIN_REGISTRY>(call, &mut its, ctx(&mut test));

    ts::next_tx(&mut test, receiver);
    let coin = ts::take_from_sender<Coin<COIN_REGISTRY>>(&mut test);

    assert!(coin::value(&coin) == (amount as u64), EValueMissmatch);

    ts::return_to_sender(&mut test, coin);

    tu::destroy(its);
    tu::destroy(channel_type);
    ts::end(test);
  }

}

#[test_only]
module dummy_its::coin_registry {
  use sui::transfer;
  use sui::coin::{Self};
  use sui::tx_context::{Self, TxContext};
  use std::option;
  use sui::url::{Url};

  /// Type is named after the module but uppercased
  struct COIN_REGISTRY has drop {}

  fun init(witness: COIN_REGISTRY, ctx: &mut TxContext) {
    let (treasuryCap, coinMetadata) = coin::create_currency(
      witness,
      18,
      b"TEST",
      b"Test Token",
      b"This is for testing",
      option::none<Url>(),
      ctx,
    );

    transfer::public_transfer(treasuryCap, tx_context::sender(ctx));
    transfer::public_transfer(coinMetadata, tx_context::sender(ctx));
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(COIN_REGISTRY {}, ctx);
  }
}