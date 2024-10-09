module squid::object_procurement;

use std::ascii::{Self, String};
use std::type_name;

use sui::coin::Coin;
use sui::bcs;

use squid::swap_info::SwapInfo;

const SWAP_TYPE: u8 = 4;

// ------
// Errors
// ------
#[error]
const EWrongObject: vector<u8> = b"object passed did not match the requested object";
#[error]
const ERemainingData: vector<u8> = b"remaining bcs data unexpected.";
#[error]
const EWrongCoinType: vector<u8> = b"coin type mismatch.";
#[error]
const EWrongSwapType: vector<u8> = b"swap type mismatch.";

// -----
// Types
// -----
public struct ObjectProcurementSwapData {
    swap_type: u8,
    object_id: ID,
    recipient: address,
    coin_type: String,
    object_type: String,
    price: u64,
    fallback: bool,
}

public fun estimate<T>(
    swap_info: &mut SwapInfo,
) {
    let (data, fallback) = swap_info.get_data_estimating();

    let swap_data = peel_swap_data(data, fallback);
    assert!(swap_data.swap_type == SWAP_TYPE, EWrongSwapType);    
    assert!(
        &swap_data.coin_type == &type_name::get<T>().into_string(),
        EWrongCoinType,
    );

    if (!fallback) { 
        swap_info.coin_bag().get_exact_estimate<T>(swap_data.price);
    };

    swap_data.destroy();
}

public fun loan_money<T>(
    swap_info: &mut SwapInfo,
    ctx: &mut TxContext,
): (ObjectProcurementSwapData, Option<Coin<T>>) {
    let (data, fallback) = swap_info.get_data_swapping();    
    
    let swap_data = peel_swap_data(data, fallback);
    assert!(swap_data.swap_type == SWAP_TYPE, EWrongSwapType);    
    assert!(
        &swap_data.coin_type == &type_name::get<T>().into_string(),
        EWrongCoinType,
    );

    if (fallback) return (swap_data, option::none());

    let balance = swap_info.coin_bag().get_exact_balance<T>(swap_data.price);
    let coin = balance.into_coin(ctx);
    (swap_data, option::some(coin))
}

public fun give_object<T: key + store>(
    swap_data: ObjectProcurementSwapData,
    object_option: Option<T>,
) {
    if(swap_data.fallback) { 
        object_option.destroy_none();
    } else {
        let object = object_option.destroy_some();
        assert!(object::id(&object) == swap_data.object_id, EWrongObject);
        transfer::public_transfer(object, swap_data.recipient);
    };
    swap_data.destroy();
}

// Store the fallback here too to be able to retreive in the `give_object`
fun peel_swap_data(data: vector<u8>, fallback: bool): ObjectProcurementSwapData {
    let mut bcs = bcs::new(data);
    let swap_data = ObjectProcurementSwapData {
        swap_type: bcs.peel_u8(),
        object_id: object::id_from_address(bcs.peel_address()),
        recipient: bcs.peel_address(),
        coin_type: ascii::string(bcs.peel_vec_u8()),
        object_type: ascii::string(bcs.peel_vec_u8()),
        price: bcs.peel_u64(),
        fallback,
    };

    assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);

    swap_data
}

fun destroy(self: ObjectProcurementSwapData) {
    let ObjectProcurementSwapData {
        swap_type: _,
        object_id: _,
        recipient: _,
        coin_type: _,
        object_type: _,
        price: _,
        fallback: _,
    } = self;
}
