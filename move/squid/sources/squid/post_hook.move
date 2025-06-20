module squid::post_hook {
    use axelar_gateway::channel::Channel;
    use relayer_discovery::transaction::{Self, MoveCall};
    use squid::{squid::Squid, swap_info::SwapInfo, swap_type::{Self, SwapType}};
    use std::{ascii::{Self, String}, type_name};
    use sui::{bcs::BCS, clock::Clock, coin, balance::Balance};
    use utils::utils::peel;

    #[error]
    const EWrongSwapType: vector<u8> = b"wrong swap type";
    #[error]
    const EWrongCoinType: vector<u8> = b"expected coin type does not match type argument";
    #[error]
    const EWrongDestinationAddress: vector<u8> = b"expected destination address does not match channel address";

    public struct PostHookSwapData has drop {
        swap_type: SwapType,
        coin_type: String,
        destination_address: address,
        move_call: MoveCall,
        fallback: bool
    }

    fun new_post_hook_swap_data(bcs: &mut BCS): PostHookSwapData {
        PostHookSwapData {
            swap_type: swap_type::peel(bcs),
            coin_type: ascii::string(bcs.peel_vec_u8()),
            destination_address: bcs.peel_address(),
            move_call: transaction::new_move_call_from_bcs(bcs),
            fallback: bcs.peel_bool(),
        }
    }

    public fun estimate<T>(swap_info: &mut SwapInfo) {
        let (data, fallback) = swap_info.data_estimating();
        let swap_data = peel!(data, |data| new_post_hook_swap_data(data));
        if (fallback != swap_data.fallback) return;

        assert!(swap_data.swap_type == swap_type::post_hook(), EWrongSwapType);

        assert!(&swap_data.coin_type == &type_name::get<T>().into_string(), EWrongCoinType);

        swap_info.coin_bag().estimate<T>();
    }

    // Call this from the move call defined in the post hook. 
    // If the swap's fallback state matces the post_hook's, then a balance should be returned.
    public fun consume_post_hook<T>(swap_info: &mut SwapInfo, channel: &Channel, ctx: &mut TxContext): Option<Balance<T>> {
        let (data, fallback) = swap_info.data_swapping();
        let swap_data = peel!(data, |data| new_post_hook_swap_data(data));

        // This check allows to skip the transfer if the `fallback` state does not
        // match the state of the transaction here.
        if (fallback != swap_data.fallback) return option::none();

        assert!(swap_data.swap_type == swap_type::post_hook(), EWrongSwapType);

        assert!(&swap_data.coin_type == &type_name::get<T>().into_string(), EWrongCoinType);

        assert!(&swap_data.destination_address == channel.to_address(), EWrongDestinationAddress);

        swap_info.coin_bag().balance<T>()
    }

    public(package) fun estimate_move_call(package_id: address, mut bcs: BCS, swap_info_arg: vector<u8>): MoveCall {
        let type_arg = ascii::string(bcs.peel_vec_u8());
        transaction::new_move_call(
            transaction::new_function(
                package_id,
                ascii::string(b"post_hook"),
                ascii::string(b"estimate"),
            ),
            vector[swap_info_arg],
            vector[type_arg],
        )
    }

    public(package) fun post_hook_move_call(mut bcs: BCS): MoveCall {
        let _type_arg = ascii::string(bcs.peel_vec_u8());
        let _destination_address = bcs.peel_address();
        let move_call = transaction::new_move_call_from_bcs(&mut bcs);
        
        move_call
    }
}
