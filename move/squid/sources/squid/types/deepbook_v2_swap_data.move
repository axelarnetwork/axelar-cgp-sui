module squid::deepbook_v2_swap_data {
    public struct DeepbookV2SwapData {
        swap_type: u8,
        pool_id: address,
        has_base: bool,
        min_output: u64,
        base_type: String,
        quote_type: String,
        lot_size: u64,
        should_sweep: bool,
    }

    entry fun new(data: vector<u8>): DeepbookV2SwapData {
        let bcs = bcs::new(data);
        DeepbookV2SwapData {
            swap_type: bcs.peel_u8(),
            pool_id: address(),
            has_base: bcs.peel_bool(),
            min_output: bcs.peel_u64(),
            base_type: ascii::string(bcs.peel_vec_u8()),
            quote_type: ascii::string(bcs.peel_vec_u8()),
            lot_size: bcs.peel_u64(),
            should_sweep: bcs.peel_bool(),
        }
    }
}