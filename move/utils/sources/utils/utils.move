/// Module: utils
module utils::utils;

use sui::bcs::{Self, BCS};

/// Remaining data after BCS decoding
const ERemainingData: u64 = 101;

public macro fun peel_data<$T>(
    $data: vector<u8>,
    $peel_fn: |&mut BCS| -> $T,
): $T {
    let mut bcs = bcs::new($data);
    let result = $peel_fn(&mut bcs);
    assert!(bcs.into_remainder_bytes().length() == 0, error_remaining_data());
    result
}

public fun error_remaining_data(): u64 { ERemainingData }
