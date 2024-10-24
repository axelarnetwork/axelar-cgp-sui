module squid::transfers;

use axelar_gateway::gateway::Gateway;
use its::its::{Self, ITS};
use its::token_id::{Self, TokenId};
use relayer_discovery::transaction::{Self, MoveCall};
use squid::squid::Squid;
use squid::swap_info::SwapInfo;
use squid::swap_type::{Self, SwapType};
use std::ascii::{Self, String};
use std::type_name;
use sui::bcs::{Self, BCS};
use sui::clock::Clock;
use sui::coin;

const EWrongSwapType: u64 = 0;
const EWrongCoinType: u64 = 1;

/// fallback states whether this transfer happens normally or only on fallback
/// mode.
public struct SuiTransferSwapData has drop {
    swap_type: SwapType,
    coin_type: String,
    recipient: address,
    fallback: bool,
}

/// fallback states whether this transfer happens normally or only on fallback
/// mode.
public struct ItsTransferSwapData has drop {
    swap_type: SwapType,
    coin_type: String,
    token_id: TokenId,
    destination_chain: String,
    destination_address: vector<u8>,
    metadata: vector<u8>,
    fallback: bool,
}

fun new_sui_transfer_swap_data(data: vector<u8>): SuiTransferSwapData {
    let mut bcs = bcs::new(data);
    SuiTransferSwapData {
        swap_type: swap_type::peel(&mut bcs),
        coin_type: ascii::string(bcs.peel_vec_u8()),
        recipient: bcs.peel_address(),
        fallback: bcs.peel_bool(),
    }
}

fun new_its_transfer_swap_data(data: vector<u8>): ItsTransferSwapData {
    let mut bcs = bcs::new(data);
    ItsTransferSwapData {
        swap_type: swap_type::peel(&mut bcs),
        coin_type: ascii::string(bcs.peel_vec_u8()),
        token_id: token_id::from_address(bcs.peel_address()),
        destination_chain: ascii::string(bcs.peel_vec_u8()),
        destination_address: bcs.peel_vec_u8(),
        metadata: bcs.peel_vec_u8(),
        fallback: bcs.peel_bool(),
    }
}

public fun sui_estimate<T>(swap_info: &mut SwapInfo) {
    let (data, fallback) = swap_info.data_estimating();
    if (fallback) return;
    let swap_data = new_sui_transfer_swap_data(data);

    assert!(swap_data.swap_type == swap_type::sui_transfer(), EWrongSwapType);

    assert!(
        &swap_data.coin_type == &type_name::get<T>().into_string(),
        EWrongCoinType,
    );

    swap_info.coin_bag().estimate<T>();
}

public fun its_estimate<T>(swap_info: &mut SwapInfo) {
    let (data, fallback) = swap_info.data_estimating();
    if (fallback) return;
    let swap_data = new_its_transfer_swap_data(data);

    assert!(swap_data.swap_type == swap_type::its_transfer(), EWrongSwapType);

    assert!(
        &swap_data.coin_type == &type_name::get<T>().into_string(),
        EWrongCoinType,
    );

    swap_info.coin_bag().estimate<T>();
}

public fun sui_transfer<T>(swap_info: &mut SwapInfo, ctx: &mut TxContext) {
    let (data, fallback) = swap_info.data_swapping();
    let swap_data = new_sui_transfer_swap_data(data);

    // This check allows to skip the transfer if the `fallback` state does not
    // match the state of the transaction here.
    if (fallback != swap_data.fallback) return;

    assert!(swap_data.swap_type == swap_type::sui_transfer(), EWrongSwapType);

    assert!(
        &swap_data.coin_type == &type_name::get<T>().into_string(),
        EWrongCoinType,
    );

    let option = swap_info.coin_bag().balance<T>();
    if (option.is_none()) {
        option.destroy_none();
        return
    };

    transfer::public_transfer(
        coin::from_balance(option.destroy_some(), ctx),
        swap_data.recipient,
    );
}

// TODO: This will break squid for now, since the MessageTicket is not submitted
// by discovery.
public fun its_transfer<T>(
    swap_info: &mut SwapInfo,
    squid: &Squid,
    its: &mut ITS,
    gateway: &Gateway,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let value = squid.value!(b"its_transfer");

    let (data, fallback) = swap_info.data_swapping();
    
    if (data.length() == 0) return;
    let swap_data = new_its_transfer_swap_data(data);

    // This check allows to skip the transfer if the `fallback` state does not
    // match the state of the transaction here.
    if (fallback != swap_data.fallback) return;

    assert!(swap_data.swap_type == swap_type::its_transfer(), EWrongSwapType);

    assert!(
        &swap_data.coin_type == &type_name::get<T>().into_string(),
        EWrongCoinType,
    );

    let option = swap_info.coin_bag().balance<T>();
    if (option.is_none()) {
        option.destroy_none();
        return
    };

    let interchain_transfer_ticket = its::prepare_interchain_transfer(
        swap_data.token_id,
        coin::from_balance(option.destroy_some(), ctx),
        swap_data.destination_chain,
        swap_data.destination_address,
        swap_data.metadata,
        value.channel(),
    );

    let message_ticket = its.send_interchain_transfer(
        interchain_transfer_ticket,
        clock,
    );
    gateway.send_message(message_ticket);
}

public(package) fun sui_estimate_move_call(
    package_id: address,
    mut bcs: BCS,
    swap_info_arg: vector<u8>,
): MoveCall {
    let type_arg = ascii::string(bcs.peel_vec_u8());
    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"transfers"),
            ascii::string(b"sui_estimate"),
        ),
        vector[swap_info_arg],
        vector[type_arg],
    )
}

public(package) fun its_estimate_move_call(
    package_id: address,
    mut bcs: BCS,
    swap_info_arg: vector<u8>,
): MoveCall {
    let type_arg = ascii::string(bcs.peel_vec_u8());
    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"transfers"),
            ascii::string(b"its_estimate"),
        ),
        vector[swap_info_arg],
        vector[type_arg],
    )
}

public(package) fun sui_transfer_move_call(
    package_id: address,
    mut bcs: BCS,
    swap_info_arg: vector<u8>,
): MoveCall {
    let type_arg = ascii::string(bcs.peel_vec_u8());
    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"transfers"),
            ascii::string(b"sui_transfer"),
        ),
        vector[swap_info_arg],
        vector[type_arg],
    )
}

public(package) fun its_transfer_move_call(
    package_id: address,
    mut bcs: BCS,
    swap_info_arg: vector<u8>,
    squid_arg: vector<u8>,
    its_arg: vector<u8>,
    gateway_arg: vector<u8>,
): MoveCall {
    let type_arg = ascii::string(bcs.peel_vec_u8());
    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"transfers"),
            ascii::string(b"its_transfer"),
        ),
        vector[swap_info_arg, squid_arg, its_arg, gateway_arg, vector[0, 6]],
        vector[type_arg],
    )
}
