module squid::object_procurement;

use relayer_discovery::transaction::{Self, MoveCall};
use squid::swap_info::SwapInfo;
use std::ascii::{Self, String};
use std::type_name;
use sui::bcs::{Self, BCS};
use sui::coin::Coin;

const SWAP_TYPE: u8 = 4;

// ------
// Errors
// ------
#[error]
const EWrongObject: vector<u8> =
    b"object passed did not match the requested object";
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
    coin_type: String,
    object_type: String,
    object_id: ID,
    recipient: address,
    price: u64,
    fallback: bool,
}

public fun estimate<T>(swap_info: &mut SwapInfo) {
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

public fun loan_coins<T>(
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

public fun return_object<T: key + store>(
    swap_data: ObjectProcurementSwapData,
    object_option: Option<T>,
) {
    if (swap_data.fallback) {
        object_option.destroy_none();
    } else {
        let object = object_option.destroy_some();
        assert!(object::id(&object) == swap_data.object_id, EWrongObject);
        transfer::public_transfer(object, swap_data.recipient);
    };
    swap_data.destroy();
}

public(package) fun get_estimate_move_call(
    package_id: address,
    mut bcs: BCS,
    swap_info_arg: vector<u8>,
): MoveCall {
    let coin_type = ascii::string(bcs.peel_vec_u8());

    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"object_procurement"),
            ascii::string(b"estimate"),
        ),
        vector[swap_info_arg],
        vector[coin_type],
    )
}

public(package) fun get_procure_move_call(
    package_id: address,
    mut bcs: BCS,
    swap_info_arg: vector<u8>,
    index: u8,
): vector<MoveCall> {
    let coin_type = ascii::string(bcs.peel_vec_u8());
    let object_type = ascii::string(bcs.peel_vec_u8());

    let swap_data_arg = vector[4, index, 0];
    let object_option_arg = vector[4, index + 1, 0];

    let loan_call = transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"object_procurement"),
            ascii::string(b"loan_coins"),
        ),
        vector[swap_info_arg],
        vector[coin_type],
    );

    let _object_id = bcs.peel_address();
    let _recipient = bcs.peel_address();
    let _price = bcs.peel_u64();

    let purchase_call = transaction::new_move_call_from_bcs(&mut bcs);

    assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);

    let return_call = transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"object_procurement"),
            ascii::string(b"return_object"),
        ),
        vector[swap_data_arg, object_option_arg],
        vector[object_type],
    );
    vector[loan_call, purchase_call, return_call]
}

// Store the fallback here too to be able to retreive in the `give_object`
fun peel_swap_data(
    data: vector<u8>,
    fallback: bool,
): ObjectProcurementSwapData {
    let mut bcs = bcs::new(data);
    let swap_data = ObjectProcurementSwapData {
        swap_type: bcs.peel_u8(),
        coin_type: ascii::string(bcs.peel_vec_u8()),
        object_type: ascii::string(bcs.peel_vec_u8()),
        object_id: object::id_from_address(bcs.peel_address()),
        recipient: bcs.peel_address(),
        price: bcs.peel_u64(),
        fallback,
    };

    transaction::new_move_call_from_bcs(&mut bcs);

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
