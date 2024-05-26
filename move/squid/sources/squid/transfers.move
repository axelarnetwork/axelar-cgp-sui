module squid::transfers {
    use std::type_name;
    use std::ascii;

    use sui::bcs::{Self, BCS};
    use sui::coin;

    use axelar::discovery::{Self, MoveCall};

    use its::service;
    use its::its::ITS;
    use its::token_id;

    use squid::swap_info::{SwapInfo};

    const SWAP_TYPE_SUI_TRANSFER: u8 = 2;
    const SWAP_TYPE_ITS_TRANSFER: u8 = 3;

    const EWrongSwapType: u64 = 0;
    const EWrongCoinType: u64 = 1;

    public fun sui_estimate<T>(swap_info: &mut SwapInfo) {
        let data = swap_info.get_data_estimating();
        if (data.length() == 0) return;
        let mut bcs = bcs::new(data);

        assert!(bcs.peel_u8() == SWAP_TYPE_SUI_TRANSFER, EWrongSwapType);

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T>().into_string().into_bytes(),
            EWrongCoinType,
        );

        swap_info.coin_bag().get_estimate<T>();
    }

    public fun its_estimate<T>(swap_info: &mut SwapInfo) {
        let data = swap_info.get_data_estimating();
        if (data.length() == 0) return;
        let mut bcs = bcs::new(data);

        assert!(bcs.peel_u8() == SWAP_TYPE_ITS_TRANSFER, EWrongSwapType);

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T>().into_string().into_bytes(),
            EWrongCoinType,
        );

        swap_info.coin_bag().get_estimate<T>();
    }

    public fun sui_transfer<T>(swap_info: &mut SwapInfo, ctx: &mut TxContext) {
        let data = swap_info.get_data_swapping();
        if (data.length() == 0) return;
        let mut bcs = bcs::new(data);

        assert!(bcs.peel_u8() == SWAP_TYPE_SUI_TRANSFER, EWrongSwapType);

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T>().into_string().into_bytes(),
            EWrongCoinType,
        );

        let option = swap_info.coin_bag().get_balance<T>();
        if(option.is_none()) {
            option.destroy_none();
            return
        };
        let address = bcs.peel_address();
        transfer::public_transfer(coin::from_balance(option.destroy_some(), ctx), address);
    }

    public fun its_transfer<T>(swap_info: &mut SwapInfo, its: &mut ITS, ctx: &mut TxContext) {
        let data = swap_info.get_data_swapping();
        if (data.length() == 0) return;
        let mut bcs = bcs::new(data);

        assert!(bcs.peel_u8() == SWAP_TYPE_SUI_TRANSFER, EWrongSwapType);

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T>().into_string().into_bytes(),
            EWrongCoinType,
        );

        let option = swap_info.coin_bag().get_balance<T>();
        if(option.is_none()) {
            option.destroy_none();
            return
        };
        let token_id = token_id::from_address(bcs.peel_address());
        let destination_chain = ascii::string(bcs.peel_vec_u8());
        let destination_address = bcs.peel_vec_u8();
        let metadata = bcs.peel_vec_u8();
        service::interchain_transfer(
            its,
            token_id,
            coin::from_balance(option.destroy_some(), ctx),
            destination_chain,
            destination_address,
            metadata,
            ctx,
        );
    }

    public(package) fun get_sui_estimate_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>): MoveCall {
        let type_arg = ascii::string(bcs.peel_vec_u8());
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"transfers"),
                ascii::string(b"sui_estimate"),
            ),
            vector[
                swap_info_arg,
            ],
            vector[type_arg],
        )
    }

    public(package) fun get_its_estimate_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>): MoveCall {
        let type_arg = ascii::string(bcs.peel_vec_u8());
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"transfers"),
                ascii::string(b"its_estimate"),
            ),
            vector[
                swap_info_arg,
            ],
            vector[type_arg],
        )
    }

    public(package) fun get_sui_transfer_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>): MoveCall {
        let type_arg = ascii::string(bcs.peel_vec_u8());
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"transfers"),
                ascii::string(b"sui_transfer"),
            ),
            vector[
                swap_info_arg,
            ],
            vector[type_arg],
        )
    }

    public(package) fun get_its_transfer_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>, its_arg: vector<u8>): MoveCall {
        let type_arg = ascii::string(bcs.peel_vec_u8());
        discovery::new_move_call(
            discovery::new_function(
                package_id,
                ascii::string(b"transfers"),
                ascii::string(b"its_transfer"),
            ),
            vector[
                swap_info_arg,
                its_arg
            ],
            vector[type_arg],
        )
    }
}
