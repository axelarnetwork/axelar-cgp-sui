module squid::sweep_dust {
    use std::type_name;

    use sui::bcs;

    use squid::swap_info::{SwapInfo};
    use squid::squid::Squid;

    const SWAP_TYPE: u8 = 0;

    const EWrongSwapType: u64 = 0;
    const EWrongCoinType: u64 = 1;

    public fun estimate<T>(swap_info: &mut SwapInfo) {

        let mut bcs = bcs::new(swap_info.get_data_estimating());

        assert!(bcs.peel_u8() == SWAP_TYPE, EWrongSwapType);

        assert!(
            &bcs.peel_vec_u8() == &type_name::get<T>().into_string().into_bytes(),
            EWrongCoinType,
        );

        swap_info.coin_bag().get_estimate<T>();
    }

    public fun sweep<T>(swap_info: &mut SwapInfo, squid: &mut Squid) {
        let data = swap_info.get_data_swapping();
        if(vector::length(&data) == 0) return;
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
}