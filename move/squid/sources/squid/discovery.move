module squid::discovery {
    use std::ascii::{Self, String};

    use sui::bcs;

    use abi::abi;

    use axelar::discovery::{Self, RelayerDiscovery, MoveCall, Transaction};

    use its::its::ITS;

    use squid::swap_info;
    use squid::squid::Squid;
    use squid::sweep_dust;
    use squid::deepbook_v2;

    const EInvalidSwapType: u64 = 0;

    const SWAP_TYPE_SWEEP_DUST: u8 = 0;
    const SWAP_TYPE_DEEPBOOK_V2: u8 = 1;

    public fun register_transaction(squid: &Squid, its: &ITS, relayer_discovery: &mut RelayerDiscovery) {
        let mut squid_arg = vector[0];
        vector::append(&mut squid_arg, object::id(squid).id_to_bytes());

        let mut its_arg = vector[0];
        vector::append(&mut its_arg, object::id(its).id_to_bytes());

        let transaction = discovery::new_transaction(
            false,
            vector[discovery::new_move_call(
                discovery::new_function(
                    discovery::package_id<Squid>(),
                    ascii::string(b"discovery"),
                    ascii::string(b"get_transaction"),
                ),
                vector[
                    squid_arg,
                    its_arg,
                    vector[3],
                ],
                vector[],
            )],
        );

        relayer_discovery.register_transaction(
            squid.borrow_channel(),
            transaction,
        )
    }

    public fun get_transaction(squid: &Squid, its: &ITS, payload: vector<u8>): Transaction {
        let (_, _, _, data) = its::discovery::get_interchain_transfer_info(payload);
        let package_id = discovery::package_id<Squid>();
        let (swap_data, type_in, _amount_in, _destination_in, type_out, _min_out, _destination_out) = swap_info::decode_swap_info_data(data);
        

        let mut squid_arg = vector[0];
        vector::append(&mut squid_arg, object::id(squid).id_to_bytes());

        let mut its_arg = vector[0];
        vector::append(&mut its_arg, object::id(its).id_to_bytes());
        let swap_info_arg = vector[4, 0, 0];

        let mut move_calls = vector [
            start_swap(package_id, squid_arg, its_arg, type_in),
        ];

        let mut i = 0;
        while(i < vector::length(&swap_data)) {
            let mut bcs = bcs::new(*vector::borrow(&swap_data, i));
            let swap_type = bcs.peel_u8();
            vector::push_back(
                &mut move_calls,
                if (swap_type == SWAP_TYPE_SWEEP_DUST) {
                    sweep_dust::get_estimate_move_call(package_id, bcs, swap_info_arg)
                } else {
                    assert!(swap_type == SWAP_TYPE_DEEPBOOK_V2, EInvalidSwapType);
                    deepbook_v2::get_estimate_move_call(package_id, bcs, swap_info_arg)
                },
            );

            i = i + 1;
        };

        vector::push_back(&mut move_calls, post_estimate(package_id, swap_info_arg, type_out));

        i = 0;
        while(i < vector::length(&swap_data)) {
            let mut bcs = bcs::new(*vector::borrow(&swap_data, i));
            let swap_type = bcs.peel_u8();

            vector::push_back(
                &mut move_calls,
                if (swap_type == SWAP_TYPE_SWEEP_DUST) {
                    sweep_dust::get_swap_move_call(package_id, bcs, swap_info_arg, squid_arg)
                } else {
                    assert!(swap_type == SWAP_TYPE_DEEPBOOK_V2, EInvalidSwapType);
                    deepbook_v2::get_swap_move_call(package_id, bcs, swap_info_arg)
                },
            );
            i = i + 1;
        };

        vector::push_back(&mut move_calls, finalize(package_id, swap_info_arg, its_arg, type_in, type_out));

        discovery::new_transaction(
            true,
            move_calls,
        )
    }

    fun start_swap(package_id: address, squid_arg: vector<u8>, its_arg: vector<u8>, type_in: String): MoveCall {
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"squid"),
                ascii::string(b"start_swap"),
            ),
            vector[
                squid_arg,
                its_arg,
                vector[2],
            ],
            vector[type_in],
        )
    }

    fun post_estimate(package_id: address, swap_info_arg: vector<u8>, type_out: String): MoveCall {
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"swap_info"),
                ascii::string(b"post_estimate"),
            ),
            vector[
                swap_info_arg,
            ],
            vector[type_out],
        )
    }

    fun finalize(package_id: address, swap_info_arg: vector<u8>, its_arg: vector<u8>, type_in: String, type_out: String): MoveCall {
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"swap_info"),
                ascii::string(b"finalize"),
            ),
            vector[
                swap_info_arg,
                its_arg,
            ],
            vector[type_in, type_out],
        )
    }
}