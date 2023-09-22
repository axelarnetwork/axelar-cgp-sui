module axelar_sui_sample::dummy_its {
  use std::string::{String};
  use std::ascii::{Self};
  use sui::object::{Self, UID};
  use sui::address::{Self};
  use sui::transfer;
  use axelar::utils::{Self};
  use axelar::channel::{Self, Channel, ApprovedCall};
  use sui::tx_context::{TxContext};
  use sui::coin::{Self, TreasuryCap, CoinMetadata, Coin};
  use sui::dynamic_field as df;
  use std::string;

  const SELECTOR_SEND_TOKEN: u256 = 1;
  const SELECTOR_SEND_TOKEN_WITH_DATA: u256 = 2;
  const SELECTOR_DEPLOY_TOKEN_MANAGER: u256 = 3;
  const SELECTOR_DEPLOY_AND_REGISTER_STANDARDIZED_TOKEN: u256 = 4;


  struct Empty has store {

  }

  struct CoinData<phantom T> has store {
    cap: TreasuryCap<T>,
    metadata: CoinMetadata<T>,
  }

  struct CoinChannel has store {
    id: UID,
  }

  struct ITS has key {
      id: UID,
      channel: Channel<Empty>,
      trusted_address: String,
  }

  struct DUMMY_ITS has drop {

  }

  fun init(_: DUMMY_ITS, ctx: &mut TxContext) {
    transfer::share_object(get_singleton_its(ctx));
  }

  fun get_singleton_its(ctx: &mut TxContext) : ITS {
    ITS {
      id: object::new(ctx),
      trusted_address: string::utf8(x"00"),
      channel: channel::create_channel<Empty>(Empty {}, ctx),
    }
  }

  public fun create_coin_channel(ctx: &mut TxContext): CoinChannel {
    CoinChannel {
        id: object::new(ctx),
    }
  }

  public fun registerCoin<T>(approved_call: ApprovedCall, its: &mut ITS, cap: TreasuryCap<T>, metadata: CoinMetadata<T>) {
    //let data: &mut Empty;
    //let source_chain: String;
    let source_address: String;
    let payload: vector<u8>;
    (
        _,
        _,
        source_address,
        payload,
    ) = channel::consume_approved_call<Empty>(
        &mut its.channel,
        approved_call,
    );
    assert!(&source_address == &its.trusted_address, 1);
    let selector = utils::abi_decode_fixed(payload, 0);

    assert!(selector == SELECTOR_DEPLOY_AND_REGISTER_STANDARDIZED_TOKEN, 1);
    let tokenId = address::from_u256(utils::abi_decode_fixed(payload, 1));


    let name = string::utf8(utils::abi_decode_variable(payload, 2));
    let symbol = ascii::string(utils::abi_decode_variable(payload, 3));
    let decimals = (utils::abi_decode_fixed(payload, 4) as u8);

    coin::update_name<T>(&cap, &mut metadata, name);
    coin::update_symbol<T>(&cap, &mut metadata, symbol);
    assert!(decimals == coin::get_decimals<T>(&metadata), 2);
      
    df::add(&mut its.id, tokenId, CoinData{cap, metadata});
  }

  fun convert_value(value: u256): u64 {
    (value as u64)
  }

  public fun receiveCoin<T>(approved_call: ApprovedCall, its: &mut ITS, ctx: &mut TxContext) {
    //let data: &mut Empty;
    //let source_chain: String;
    let source_address: String;
    let payload: vector<u8>;
    (
        _,
        _,
        source_address,
        payload,
    ) = channel::consume_approved_call<Empty>(
        &mut its.channel,
        approved_call,
    );
    assert!(&source_address == &its.trusted_address, 1);
    let selector = utils::abi_decode_fixed(payload, 0);
    
    assert!(selector == SELECTOR_SEND_TOKEN, 1);
    let tokenId = address::from_u256(utils::abi_decode_fixed(payload, 1));
      
    let cap = &mut df::borrow_mut<address, CoinData<T>>(&mut its.id, tokenId).cap;
    let destination_address = address::from_bytes(utils::abi_decode_variable(payload, 2));
    let value = convert_value(utils::abi_decode_fixed(payload, 3));
    coin::mint_and_transfer<T>(cap, value, destination_address, ctx);
  }

  public fun receiveCoinWithData<T>(approved_call: ApprovedCall, its: &mut ITS, channel: &CoinChannel, ctx: &mut TxContext): (Coin<T>, String, vector<u8>, vector<u8>) {
    //let data: &mut Empty;
    let source_chain: String;
    let source_address: String;
    let payload: vector<u8>;
    (
        _,
        source_chain,
        source_address,
        payload,
    ) = channel::consume_approved_call<Empty>(
        &mut its.channel,
        approved_call,
    );
    assert!(&source_address == &its.trusted_address, 1);
    let selector = utils::abi_decode_fixed(payload, 0);
    
    assert!(selector == SELECTOR_SEND_TOKEN, 2);
    let tokenId = address::from_u256(utils::abi_decode_fixed(payload, 1));
      
    let cap = df::borrow_mut<address, TreasuryCap<T>>(&mut its.id, tokenId);
    let destination_address = address::from_u256(utils::abi_decode_fixed(payload, 2));

    assert!(object::uid_to_address(&channel.id) == destination_address, 3);

    let value = convert_value(utils::abi_decode_fixed(payload, 3));
    let coin_source_address = utils::abi_decode_variable(payload, 4);
    let data = utils::abi_decode_variable(payload, 5);
    let coin = coin::mint<T>(cap, value, ctx);
    (
      coin,
      source_chain,
      coin_source_address,
      data,
    )
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
    use axelar_sui_sample::coin_registry::{Self, COIN_REGISTRY};
    
    let payload = utils::abi_encode_start(9);
    utils::abi_encode_fixed(&mut payload, 0, SELECTOR_DEPLOY_AND_REGISTER_STANDARDIZED_TOKEN);
    utils::abi_encode_fixed(&mut payload, 1, TOKEN_ID);
    utils::abi_encode_variable(&mut payload, 2, b"Token Name");
    utils::abi_encode_variable(&mut payload, 3, b"SYMBOL");
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
    registerCoin<COIN_REGISTRY>(call, its, treasuryCap, coinMetadata);
  }
  #[test]
  fun test_register_coin() {   
    use sui::test_scenario::{Self as ts, ctx};
    use sui::test_utils::{Self as tu};

    let test = ts::begin(@0x0);
    let its = get_singleton_its(ctx(&mut test));

    register_coin(&mut test, &mut its);

    tu::destroy(its);
    ts::end(test);
  }


  #[test]
  fun test_receive_coin() {   
    use sui::test_scenario::{Self as ts, ctx};
    use sui::test_utils::{Self as tu};
    use axelar_sui_sample::coin_registry::{COIN_REGISTRY};

    let test = ts::begin(@0x0);
    let its = get_singleton_its(ctx(&mut test));

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
    receiveCoin<COIN_REGISTRY>(call, &mut its, ctx(&mut test));

    ts::next_tx(&mut test, receiver);
    let coin = ts::take_from_sender<Coin<COIN_REGISTRY>>(&mut test);

    assert!(coin::value(&coin) == (amount as u64), 3);

    ts::return_to_sender(&mut test, coin);

    tu::destroy(its);
    ts::end(test);
  }

}

#[test_only]
module axelar_sui_sample::coin_registry {
  use sui::transfer;
  use sui::coin::{Self};
  use sui::tx_context::{Self, TxContext};

  /// Type is named after the module but uppercased
  struct COIN_REGISTRY has drop {}

  fun init(witness: COIN_REGISTRY, ctx: &mut TxContext) {
    let (treasuryCap, coinMetadata) = coin::create_currency(
      witness,
      18,
      b"TEST",
      b"Test Token",
      b"This is for testing",
      std::option::some(sui::url::new_unsafe_from_bytes(b"a url")),
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