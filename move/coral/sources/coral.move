module coral::coral;

use axelar_gateway::bytes32::{Self, Bytes32};
use sui::balance::Balance;
use std::type_name::{Self, TypeName};
use sui::coin::Coin;
use sui::bag::Bag;
use sui::clock::Clock;
use axelar_gateway::channel::{Channel, ApprovedMessage};

#[error]
const EError: vector<u8> = b"error description";

public struct Coral has key {
    id: UID,
    orders: Bag,
    settlements: Bag,
    fees: Bag,
    channel: Channel,
}

public struct Order<phantom T> has copy, store, drop {
    // Address that will supply the fromAmount of fromToken on the fromChain.
    fromAddress: address,
    // Address to receive the fillAmount of toToken on the toChain.
    toAddress: vector<u8>,
    // Address that will fill the Order on the toChain.
    filler: vector<u8>,
    // Address of the ERC20 token being supplied on the toChain.
    // 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE in case of native token.
    toToken: vector<u8>,
    // Expiration in UNIX for the Order to be created on the fromChain.
    expiry: u64,
    // Amount of fromToken to be provided by the fromAddress.
    fromAmount: u64,
    // Amount of toToken to be provided by the filler.
    fillAmount: u256,
    // Protocol fees are taken out of the fromAmount and are calculated within the Spoke.sol
    // contract for single chain orders or on the Hub for cross chain orders. 
    // The following formula determines the amount of fromToken reserved as fees:
    // fee = (fromAmount * feeRate) / 1000000
    feeRate: u256,
    // Chain ID of the chain the Order will be created on.
    fromChain: u256,
    // Chain ID of the chain the Order will be filled on.
    toChain: u256,
    // Keccak256 hash of the abi.encoded ISquidMulticall.Call[] calldata calls that should be provided
    // at the time of filling the order.
    postHookHash: Bytes32,
}

public struct Settlement<phantom T> has copy, store, drop {
    // Address that will supply the fromAmount of fromToken on the fromChain.
    fromAddress: vector<u8>,
    // Address to receive the fillAmount of toToken on the toChain.
    toAddress: address,
    // Address that will fill the Order on the toChain.
    filler: address,
    // Address of the ERC20 token being supplied on the toChain.
    // 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE in case of native token.
    fromToken: vector<u8>,
    // Expiration in UNIX for the Order to be created on the fromChain.
    expiry: u64,
    // Amount of fromToken to be provided by the fromAddress.
    fromAmount: u256,
    // Amount of toToken to be provided by the filler.
    fillAmount: u64,
    // Protocol fees are taken out of the fromAmount and are calculated within the Spoke.sol
    // contract for single chain orders or on the Hub for cross chain orders. 
    // The following formula determines the amount of fromToken reserved as fees:
    // fee = (fromAmount * feeRate) / 1000000
    feeRate: u256,
    // Chain ID of the chain the Order will be created on.
    fromChain: u256,
    // Chain ID of the chain the Order will be filled on.
    toChain: u256,
    // Keccak256 hash of the abi.encoded ISquidMulticall.Call[] calldata calls that should be provided
    // at the time of filling the order.
    postHookHash: Bytes32,
}

public enum OrderStatus<T: store> has store {
    // Order has been created, pending settlement.
    Created(Balance<T>),
    // Order has been settled.
    Settled(),
    // Order has been refunded.
    Refunded(),
}

public struct OrderFill has drop, store {
    type_name: TypeName,
    orderHash: Bytes32,
    filler: address,
    fromAmount: u64,
    processedFee: u64,
}

public struct OrderFills {
    index: u64,
    order_fills: vector<OrderFill>,
}

public fun new_order<T>(
    fromAddress: address,
    toAddress: vector<u8>,
    filler: vector<u8>,
    toToken: vector<u8>,
    expiry: u64,
    fromAmount: u64,
    fillAmount: u256,
    feeRate: u256,
    fromChain: u256,
    toChain: u256,
    postHookHash: Bytes32,
): Order<T> {
    Order<T> {
        fromAddress,
        toAddress,
        filler,
        toToken,
        expiry,
        fromAmount,
        fillAmount,
        feeRate,
        fromChain,
        toChain,
        postHookHash,
    }
}

public fun create_order<T: store>(coral: &mut Coral, order: Order<T>, coin: Coin<T>, clock: &Clock) {
    let hash = order.hash();

    assert!(!coral.orders.contains(hash), EError);
    assert!(clock.timestamp_ms() <= order.expiry, EError);    
    assert!(coin.value() == order.fromAmount && order.fromAmount > 0, EError);

    coral.orders.add(hash, OrderStatus<T>::Created(coin.into_balance()));
}

public fun fill_order<T>(coral: &Coral, settlement: Settlement, coin<T>) {
    let hash = order.hash();

    // asserts
    assert!(!coral.settlements.cointains(hash), EError);

    transfer::public_transfer(coin, settlement.toAddress);

    settlements.add(hash, true);    
}

// include T in hashing.
fun hash<T>(order: Order<T>): Bytes32 {
    bytes32::new(@0x0)
}

fun receive_call(self: &Coral, approved_message: ApprovedMessage): OrderFills {
    let (source_chain, message_id, source_address, payload) = self
        .channel
        .consume_approved_message(approved_message);
    
    // make sure it comes from the hub.

    // decode payload and created OrderFills object

    OrderFills {
        index: 0,
        order_fills: vector<OrderFill>[],
    }
}

fun releaseToken<T: store>(
    coral: &mut Coral,
    order_fills: &mut OrderFills,
    ctx: &mut TxContext,
) {
    let order_fill = &order_fills.order_fills[order_fills.index];
    order_fills.index = order_fills.index + 1;

    /*
    assert!(type_name::get<T>() == order_fill.type_name, EError);

    let order: OrderStatus<T> = coral.orders.remove(order_fill.orderHash);
    let mut balance: Balance<T> = match(order) {
        OrderStatus<T>::Created( balance ) => balance,
        _ => abort(EError),
    };
    assert!(order_fill.fromAmount == balance.value(), EError);
    let fee = balance.split(order_fill.processedFee);
    coral.add_fee<T>(fee);
    let coin = balance.into_coin(ctx);
    transfer::public_transfer(coin, filler);
    */
}

fun finalize(order_fills: OrderFills) {
    let OrderFills{ index, order_fills: inner } = order_fills;
    assert!(index == inner.length(), EError);
}

fun add_fee<T: store>(self: &mut Coral, fee: Balance<T>) {
    let type_name = type_name::get<T>();
    if (!self.fees.contains(type_name)) {
        self.fees.add(type_name, fee);
    } else {
        let stored_balance: &mut Balance<T> = self.fees.borrow_mut(type_name);
        stored_balance.join(fee);
    }
}
