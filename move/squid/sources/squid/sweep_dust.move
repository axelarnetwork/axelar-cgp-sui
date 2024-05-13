module squid::sweep_dust {
    use std::type_name;
    use std::ascii;

    use sui::bcs::{Self, BCS};

    use axelar::discovery::{Self, MoveCall};

    use squid::swap_info::{SwapInfo};
    use squid::squid::Squid;

    const SWAP_TYPE: u8 = 0;

    const EWrongSwapType: u64 = 0;
    const EWrongCoinType: u64 = 1;

    public fun estimate<T>(swap_info: &mut SwapInfo) {
        let data = swap_info.get_data_estimating();
        if (vector::length(&data) == 0) return;
        let mut bcs = bcs::new(data);

        assert!(bcs.peel_u8() == SWAP_TYPE, EWrongSwapType);

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T>().into_string().into_bytes(),
            EWrongCoinType,
        );

        swap_info.coin_bag().get_estimate<T>();
    }

    public fun sweep<T>(swap_info: &mut SwapInfo, squid: &mut Squid) {
        let data = swap_info.get_data_swapping();
        if (vector::length(&data) == 0) return;
        let mut bcs = bcs::new(data);

        assert!(bcs.peel_u8() == SWAP_TYPE, EWrongSwapType);

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T>().into_string().into_bytes(),
            EWrongCoinType,
        );

        let option = swap_info.coin_bag().get_balance<T>();
        if(option.is_none()) {
            option.destroy_none();
            return
        };
        squid.coin_bag().store_balance(option.destroy_some());
    }

    public(package) fun get_estimate_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>): MoveCall {
        let type_arg = ascii::string(bcs.peel_vec_u8());
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"sweep_dust"),
                ascii::string(b"estimate"),
            ),
            vector[
                swap_info_arg,
            ],
            vector[type_arg],
        )
    }

    public(package) fun get_swap_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>, squid_arg: vector<u8>): MoveCall {
        let type_arg = ascii::string(bcs.peel_vec_u8());
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"sweep_dust"),
                ascii::string(b"sweep"),
            ),
            vector[
                swap_info_arg,
                squid_arg
            ],
            vector[type_arg],
        )
    }
}