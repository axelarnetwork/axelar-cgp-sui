module squid::swap_info {
    use sui::bcs;

    use squid::coin_bag::{Self, CoinBag};

    public struct SwapInfo {
        swap_index: u64,
        estimate_index: u64,
        status: u8,
        swap_data: vector<vector<u8>>,
        coin_bag: CoinBag,
    }

    const ESTIMATING: u8 = 0;
    const SWAPPING: u8 = 1;
    const SKIP_SWAP: u8 = 2;

    const EOutOfEstimates: u64 = 0;
    const EOutOfSwaps: u64 = 1;
    const ENotEstimating: u64 = 3;
    const ENotSwapping: u64 = 4;
    const ENotDoneEstimating: u64 = 5;
    const ENotDoneSwapping: u64 = 6;


    public(package) fun new(data: vector<u8>, ctx: &mut TxContext): SwapInfo {
        let swap_data = bcs::new(data).peel_vec_vec_u8();
        SwapInfo {
            swap_index: 0,
            estimate_index: 0,
            status: ESTIMATING,
            coin_bag: coin_bag::new(ctx),

            swap_data,
        }
    }

    public(package) fun get_data_swapping(self: &mut SwapInfo): vector<u8> {
        let index = self.swap_index;
        if (index == 0 && self.status == ESTIMATING) {
            assert!(self.estimate_index == self.swap_data.length(), ENotDoneEstimating);
            self.status = SWAPPING;
        };
        assert!(index < self.swap_data.length(), EOutOfSwaps);

        self.swap_index = index + 1;
        if (self.status == SKIP_SWAP) {
            vector[]
        } else {
            assert!(self.status == SWAPPING, ENotSwapping);
            self.swap_data[index]
        }
    }

    public(package) fun get_data_estimating(self: &mut SwapInfo): vector<u8> {
        let index = self.estimate_index;
        assert!(index < self.swap_data.length(), EOutOfEstimates);

        self.estimate_index = index + 1;

        if (self.status == SKIP_SWAP) {
            vector[]
        } else {
            assert!(self.status == ESTIMATING, ENotEstimating);
            self.swap_data[index]
        }
    }

    public(package) fun coin_bag(self: &mut SwapInfo): &mut CoinBag {
        &mut self.coin_bag
    }

    public(package) fun swap_data(self: &SwapInfo, i: u64): vector<u8> {
        self.swap_data[i]
    }

    public(package) fun skip_swap(self: &mut SwapInfo) {
        self.status = SKIP_SWAP;
    }

    public fun finalize(self: SwapInfo) {
        assert!(
            self.estimate_index == self.swap_data.length() &&
            self.swap_index == self.swap_data.length(),
            ENotDoneSwapping,
        );
        assert!(
            self.status == SWAPPING ||
            self.status == SKIP_SWAP, ENotDoneEstimating
        );
        self.destroy();
    }

    fun destroy(self: SwapInfo) {
        let SwapInfo {
            swap_index: _,
            estimate_index: _,
            swap_data: _,
            status: _,
            coin_bag,
        } = self;
        coin_bag.destroy();
    }

    #[test]
    fun test_swap_data() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);

        assert!(swap_info.get_data_estimating() == swap1, 0);
        assert!(swap_info.get_data_estimating() == swap2, 0);
        assert!(swap_info.get_data_swapping() == swap1, 0);
        assert!(swap_info.get_data_swapping() == swap2, 0);

        swap_info.finalize();
    }

    #[test]
    #[expected_failure(abort_code = ENotDoneEstimating)]
    fun test_get_data_swapping_not_done_estimating() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);

        swap_info.get_data_swapping();

        swap_info.destroy();
    }

    #[test]
    #[expected_failure(abort_code = ENotSwapping)]
    fun test_get_data_swapping_not_swapping() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);
        swap_info.swap_index = 1;

        swap_info.get_data_swapping();

        swap_info.destroy();
    }

    #[test]
    #[expected_failure(abort_code = EOutOfSwaps)]
    fun test_get_data_swapping_out_of_swaps() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);
        swap_info.swap_index = 2;

        swap_info.get_data_swapping();

        swap_info.destroy();
    }

    #[test]
    fun test_get_data_swapping_skip_swap() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);
        swap_info.skip_swap();

        swap_info.get_data_swapping();

        swap_info.destroy();
    }

    #[test]
    #[expected_failure(abort_code = EOutOfEstimates)]
    fun test_get_data_estimating_out_of_swaps() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);
        swap_info.estimate_index = 2;

        swap_info.get_data_estimating();

        swap_info.destroy();
    }

    #[test]
    #[expected_failure(abort_code = ENotEstimating)]
    fun test_get_data_estimating_not_estimating() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);
        swap_info.status = SWAPPING;

        swap_info.get_data_estimating();

        swap_info.destroy();
    }

    #[test]
    fun test_get_data_estimating_skip_swap() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);
        swap_info.skip_swap();

        swap_info.get_data_estimating();

        swap_info.destroy();
    }

    #[test]
    #[expected_failure(abort_code = ENotDoneSwapping)]
    fun test_finalize_not_done_swapping() {
        let ctx = &mut tx_context::dummy();

        let swap1 = b"1";
        let swap2 = b"2";

        let data = std::bcs::to_bytes(&vector[
            swap1,
            swap2,
        ]);

        let mut swap_info = new(data, ctx);
        swap_info.status = SWAPPING;

        swap_info.finalize();
    }

    #[test]
    #[expected_failure(abort_code = ENotDoneEstimating)]
    fun test_finalize_not_done_estimating() {
        let ctx = &mut tx_context::dummy();

        let data = std::bcs::to_bytes(&vector<vector<u8>>[]);

        let swap_info = new(data, ctx);

        swap_info.finalize();
    }
}
