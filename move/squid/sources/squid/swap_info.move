module squid::swap_info;

use squid::coin_bag::{Self, CoinBag};
use sui::bcs;

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
        assert!(
            self.estimate_index == self.swap_data.length(),
            ENotDoneEstimating,
        );
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
        self.status == SKIP_SWAP,
        ENotDoneSwapping,
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
