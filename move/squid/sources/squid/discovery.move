module squid::discovery;

use std::ascii::{Self, String};

use sui::bcs;

use axelar_gateway::gateway::Gateway;

use relayer_discovery::discovery::RelayerDiscovery;
use relayer_discovery::transaction::{Self, MoveCall, Transaction};

use its::its::ITS;

use squid::deepbook_v3;
use squid::squid::Squid;
use squid::transfers;

const EInvalidSwapType: u64 = 0;

const SWAP_TYPE_DEEPBOOK_V3: u8 = 1;
const SWAP_TYPE_SUI_TRANSFER: u8 = 2;
const SWAP_TYPE_ITS_TRANSFER: u8 = 3;

public fun register_transaction(
    squid: &Squid,
    its: &ITS,
    gateway: &Gateway,
    relayer_discovery: &mut RelayerDiscovery,
) {
    let mut squid_arg = vector[0];
    squid_arg.append(object::id(squid).id_to_bytes());

    let mut its_arg = vector[0];
    its_arg.append(object::id(its).id_to_bytes());

    let mut gateway_arg = vector[0];
    gateway_arg.append(object::id(gateway).id_to_bytes());

    let transaction = transaction::new_transaction(
        false,
        vector[
            transaction::new_move_call(
                transaction::new_function(
                    transaction::package_id<Squid>(),
                    ascii::string(b"discovery"),
                    ascii::string(b"get_transaction"),
                ),
                vector[squid_arg, its_arg, gateway_arg, vector[3]],
                vector[],
            ),
        ],
    );

    relayer_discovery.register_transaction(
        squid.value!(b"register_transaction").channel(),
        transaction,
    )
}

public fun transaction(
    squid: &Squid,
    its: &ITS,
    gateway: &Gateway,
    payload: vector<u8>,
): Transaction {
    let (token_id, _, _, data) = its::discovery::interchain_transfer_info(
        payload,
    );
    let type_in = (*its.registered_coin_type(token_id)).into_string();
    let package_id = transaction::package_id<Squid>();
    let swap_data = bcs::new(data).peel_vec_vec_u8();

    let mut squid_arg = vector[0];
    squid_arg.append(object::id(squid).id_to_bytes());

    let mut its_arg = vector[0];
    its_arg.append(object::id(its).id_to_bytes());

    let mut gateway_arg = vector[0];
    gateway_arg.append(object::id(gateway).id_to_bytes());

    let swap_info_arg = vector[4, 0, 0];

    let mut move_calls = vector[
        start_swap(package_id, squid_arg, its_arg, type_in),
    ];

    let mut i = 0;
    while (i < swap_data.length()) {
        let mut bcs = bcs::new(swap_data[i]);
        let swap_type = bcs.peel_u8();

        if (swap_type == SWAP_TYPE_DEEPBOOK_V3) {
            move_calls.push_back(
                deepbook_v3::estimate_move_call(
                    package_id,
                    bcs,
                    swap_info_arg,
                ),
            );
        } else if (swap_type == SWAP_TYPE_SUI_TRANSFER) {
            move_calls.push_back(
                transfers::sui_estimate_move_call(
                    package_id,
                    bcs,
                    swap_info_arg,
                ),
            );
        } else {
            assert!(swap_type == SWAP_TYPE_ITS_TRANSFER, EInvalidSwapType);
            move_calls.push_back(
                transfers::its_estimate_move_call(
                    package_id,
                    bcs,
                    swap_info_arg,
                ),
            );
        };

        i = i + 1;
    };

    i = 0;
    while (i < swap_data.length()) {
        let mut bcs = bcs::new(swap_data[i]);
        let swap_type = bcs.peel_u8();

        if (swap_type == SWAP_TYPE_DEEPBOOK_V3) {
            move_calls.push_back(
                deepbook_v3::swap_move_call(
                    package_id,
                    bcs,
                    swap_info_arg,
                    squid_arg,
                ),
            );
        } else if (swap_type == SWAP_TYPE_SUI_TRANSFER) {
            move_calls.push_back(
                transfers::sui_transfer_move_call(
                    package_id,
                    bcs,
                    swap_info_arg,
                ),
            );
        } else {
            assert!(swap_type == SWAP_TYPE_ITS_TRANSFER, EInvalidSwapType);
            move_calls.push_back(
                transfers::its_transfer_move_call(
                    package_id,
                    bcs,
                    swap_info_arg,
                    squid_arg,
                    gateway_arg,
                    its_arg,
                ),
            );
        };

        i = i + 1;
    };

    move_calls.push_back(finalize(package_id, swap_info_arg));

    transaction::new_transaction(
        true,
        move_calls,
    )
}

fun start_swap(
    package_id: address,
    squid_arg: vector<u8>,
    its_arg: vector<u8>,
    type_in: String,
): MoveCall {
    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"squid"),
            ascii::string(b"start_swap"),
        ),
        vector[squid_arg, its_arg, vector[2], vector[0, 6]],
        vector[type_in],
    )
}

fun finalize(package_id: address, swap_info_arg: vector<u8>): MoveCall {
    transaction::new_move_call(
        transaction::new_function(
            package_id,
            ascii::string(b"squid"),
            ascii::string(b"finalize"),
        ),
        vector[swap_info_arg],
        vector[],
    )
}
