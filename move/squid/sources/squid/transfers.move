module squid::transfers {
    use std::type_name;
    use std::ascii::{Self, String};

    use sui::bcs::{Self, BCS};
    use sui::coin;

    use axelar_gateway::discovery::{Self, MoveCall};

    use its::service;
    use its::its::ITS;
    use its::token_id::{Self, TokenId};

    use squid::swap_info::{SwapInfo};

    const SWAP_TYPE_SUI_TRANSFER: u8 = 2;
    const SWAP_TYPE_ITS_TRANSFER: u8 = 3;

    const EWrongSwapType: u64 = 0;
    const EWrongCoinType: u64 = 1;

    public struct SuiTransferSwapData has drop {
        swap_type: u8,
        coin_type: String,
        recipient: address,
    }

    public struct ItsTransferSwapData has drop {
        swap_type: u8,
        coin_type: String,
        token_id: TokenId,
        destination_chain: String,
        destination_address: vector<u8>,
        metadata: vector<u8>,
    }

    fun new_sui_transfer_swap_data(data: vector<u8>): SuiTransferSwapData {
        let mut bcs = bcs::new(data);
        SuiTransferSwapData {
            swap_type: bcs.peel_u8(),
            coin_type: ascii::string(bcs.peel_vec_u8()),
            recipient: bcs.peel_address(),
        }
    }

    fun new_its_transfer_swap_data(data: vector<u8>): ItsTransferSwapData {
        let mut bcs = bcs::new(data);
        ItsTransferSwapData {
            swap_type: bcs.peel_u8(),
            coin_type: ascii::string(bcs.peel_vec_u8()),
            token_id: token_id::from_address(bcs.peel_address()),
            destination_chain: ascii::string(bcs.peel_vec_u8()),
            destination_address: bcs.peel_vec_u8(),
            metadata: bcs.peel_vec_u8(),
        }
    }

    public fun sui_estimate<T>(swap_info: &mut SwapInfo) {
        let data = swap_info.get_data_estimating();
        if (data.length() == 0) return;
        let swap_data = new_sui_transfer_swap_data(data);

        assert!(swap_data.swap_type == SWAP_TYPE_SUI_TRANSFER, EWrongSwapType);

        assert!(
            &swap_data.coin_type == &type_name::get<T>().into_string(),
            EWrongCoinType,
        );

        swap_info.coin_bag().get_estimate<T>();
    }

    public fun its_estimate<T>(swap_info: &mut SwapInfo) {
        let data = swap_info.get_data_estimating();
        if (data.length() == 0) return;
        let swap_data = new_its_transfer_swap_data(data);

        assert!(swap_data.swap_type == SWAP_TYPE_ITS_TRANSFER, EWrongSwapType);

        assert!(
            &swap_data.coin_type == &type_name::get<T>().into_string(),
            EWrongCoinType,
        );

        swap_info.coin_bag().get_estimate<T>();
    }

    public fun sui_transfer<T>(swap_info: &mut SwapInfo, ctx: &mut TxContext) {
        let data = swap_info.get_data_swapping();
        if (data.length() == 0) return;
        let swap_data = new_sui_transfer_swap_data(data);

        assert!(swap_data.swap_type == SWAP_TYPE_SUI_TRANSFER, EWrongSwapType);

        assert!(
            &swap_data.coin_type == &type_name::get<T>().into_string(),
            EWrongCoinType,
        );

        let option = swap_info.coin_bag().get_balance<T>();
        if(option.is_none()) {
            option.destroy_none();
            return
        };
        
        transfer::public_transfer(coin::from_balance(option.destroy_some(), ctx), swap_data.recipient);
    }

    public fun its_transfer<T>(swap_info: &mut SwapInfo, its: &mut ITS, ctx: &mut TxContext) {
        let data = swap_info.get_data_swapping();
        if (data.length() == 0) return;
        let swap_data = new_its_transfer_swap_data(data);

        assert!(swap_data.swap_type == SWAP_TYPE_SUI_TRANSFER, EWrongSwapType);

        assert!(
            &swap_data.coin_type == &type_name::get<T>().into_string(),
            EWrongCoinType,
        );

        let option = swap_info.coin_bag().get_balance<T>();
        if(option.is_none()) {
            option.destroy_none();
            return
        };
        
        service::interchain_transfer(
            its,
            swap_data.token_id,
            coin::from_balance(option.destroy_some(), ctx),
            swap_data.destination_chain,
            swap_data.destination_address,
            swap_data.metadata,
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
