module squid::swap_info;

use squid::coin_bag::{Self, CoinBag};
use sui::bcs;

// -----
// Enums
// -----
/// Swapping: Curently performing swaps, should happen only after all estimation is finished.
/// Estimating: Currently performing estimates. Once all estimates are done and the output is satisfactory then we can swap.
/// Done: Done swapping and can be destroyed.
public enum SwapStatus has copy, drop, store {
    Swapping { 
        index: u64, 
        fallback: bool 
    },
    Estimating { 
        index: u64, 
        fallback: bool 
    },
    Done,
}

// -----
// Types
// -----
public struct SwapInfo {
    status: SwapStatus,
    swap_data: vector<vector<u8>>,
    coin_bag: CoinBag,
}

// ------
// Errors
// ------
#[error]
const EOutOfEstimates: vector<u8> =
    b"trying to get make an estimate but there are none left.";
#[error]
const EOutOfSwaps: vector<u8> =
    b"trying to get make a swap but there are none left.";
#[error]
const ENotEstimating: vector<u8> =
    b"trying to get an estimate but estimating is done.";
#[error]
const ENotDoneEstimating: vector<u8> = b"trying to swap while still swapping.";
#[error]
const EDoneSwapping: vector<u8> = b"trying to swap but swapping is finished.";
#[error]
const EAlreadySkippingSwaps: vector<u8> =
    b"trying to skip swaps while swaps are skipped.";
#[error]
const ENotDone: vector<u8> =
    b"trying to finalize but SwapInfo is not Done yet.";
#[error]
const EDoneEstimating: vector<u8> =
    b"trying to estimate but estimating is finished.";

// -----------------
// Package Functions
// -----------------
public(package) fun new(data: vector<u8>, ctx: &mut TxContext): SwapInfo {
    let swap_data = bcs::new(data).peel_vec_vec_u8();
    SwapInfo {
        status: SwapStatus::Estimating { index: 0, fallback: false },
        coin_bag: coin_bag::new(ctx),
        swap_data,
    }
}

public(package) fun data_swapping(self: &mut SwapInfo): (vector<u8>, bool) {
    let (index, fallback) = match (self.status) {
        SwapStatus::Swapping { index, fallback } => (index, fallback),
        SwapStatus::Estimating { .. } => abort (
            ENotDoneEstimating,
        ),
        SwapStatus::Done => abort (EDoneSwapping),
    };

    assert!(index < self.swap_data.length(), EOutOfSwaps);

    self.status = if (index + 1 < self.swap_data.length()) {
            SwapStatus::Swapping { index: index + 1, fallback }
        } else {
            SwapStatus::Done
        };

    (self.swap_data[index], fallback)
}

public(package) fun data_estimating(
    self: &mut SwapInfo,
): (vector<u8>, bool) {
    let (index, fallback) = match (self.status) {
        SwapStatus::Estimating { index, fallback } => (index, fallback),
        _ => abort (EDoneEstimating),
    };

    assert!(index < self.swap_data.length(), EOutOfEstimates);

    self.status = if (index + 1 < self.swap_data.length()) {
            SwapStatus::Estimating { index: index + 1, fallback }
        } else {
            SwapStatus::Swapping { index: 0, fallback }
        };

    (self.swap_data[index], fallback)
}

public(package) fun coin_bag(self: &mut SwapInfo): &mut CoinBag {
    &mut self.coin_bag
}

public(package) fun skip_swap(self: &mut SwapInfo) {
    self.status =
        match (self.status) {
            SwapStatus::Estimating { index, fallback: false } => SwapStatus::Estimating { index, fallback: true },
            SwapStatus::Estimating { .. } => abort (EAlreadySkippingSwaps),
            _ => abort (ENotEstimating),
        };
}

public(package) fun finalize(self: SwapInfo) {
    match (self.status) {
        SwapStatus::Done => self.destroy(),
        _ => abort (ENotDone),
    };
}

fun destroy(self: SwapInfo) {
    let SwapInfo {
        status: _,
        swap_data: _,
        coin_bag,
    } = self;
    coin_bag.destroy();
}

#[test]
fun test_swap_data() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);

    let (mut data, _) = swap_info.data_estimating();
    assert!(data == swap1);
    (data, _) = swap_info.data_estimating();
    assert!(data == swap2);
    (data, _) = swap_info.data_swapping();
    assert!(data == swap1);
    (data, _) = swap_info.data_swapping();
    assert!(data == swap2);

    swap_info.finalize();
}

#[test]
#[expected_failure(abort_code = ENotDoneEstimating)]
fun test_get_data_swapping_not_done_estimating() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);

    swap_info.data_swapping();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = EDoneSwapping)]
fun test_get_data_swapping_done_swapping() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Done;

    swap_info.data_swapping();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = EOutOfSwaps)]
fun test_get_data_swapping_out_of_swaps() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Swapping { index: 2, fallback: false };

    swap_info.data_swapping();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = EAlreadySkippingSwaps)]
fun test_skip_swap_already_skipped_swaps() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);

    swap_info.skip_swap();
    swap_info.skip_swap();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = ENotEstimating)]
fun test_skip_swap_already_not_estimating_swapping() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Swapping { index: 0, fallback: false };

    swap_info.skip_swap();
    swap_info.skip_swap();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = ENotEstimating)]
fun test_skip_swap_already_not_estimating_done() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Done;

    swap_info.skip_swap();
    swap_info.skip_swap();

    swap_info.destroy();
}

#[test]
fun test_get_data_swapping_skip_swap() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Swapping { index: 0, fallback: true };

    swap_info.data_swapping();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = EOutOfEstimates)]
fun test_get_data_estimating_out_of_swaps() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Estimating { index: 2, fallback: false };

    swap_info.data_estimating();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = EDoneEstimating)]
fun test_get_data_estimating_swapping() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Swapping { index: 0, fallback: false };

    swap_info.data_estimating();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = EDoneEstimating)]
fun test_get_data_estimating_done() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Done;

    swap_info.data_estimating();

    swap_info.destroy();
}

#[test]
fun test_get_data_estimating_skip_swap() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.skip_swap();

    swap_info.data_estimating();

    swap_info.destroy();
}

#[test]
#[expected_failure(abort_code = ENotDone)]
fun test_finalize_not_done_swapping() {
    let ctx = &mut tx_context::dummy();

    let swap1 = b"1";
    let swap2 = b"2";

    let data = std::bcs::to_bytes(&vector[swap1, swap2]);

    let mut swap_info = new(data, ctx);
    swap_info.status = SwapStatus::Swapping { index: 0, fallback: false };

    swap_info.finalize();
}

#[test]
#[expected_failure(abort_code = ENotDone)]
fun test_finalize_not_done_estimating() {
    let ctx = &mut tx_context::dummy();

    let data = std::bcs::to_bytes(&vector<vector<u8>>[]);

    let swap_info = new(data, ctx);

    swap_info.finalize();
}
