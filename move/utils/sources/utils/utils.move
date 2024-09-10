/// Module: utils
module utils::utils;

use sui::bcs::{Self, BCS};

// -----
// Error
// ----
const ERemainingData: u64 = 101;

// -----
// Macros
// -----

/**
* Peel data from a BCS encoded vector
* @dev This macro is used to peel data from a BCS encoded vector
* @param $data The BCS encoded vector
* @param $peel_fn The function to peel the data
* @returns The peeled data
*/
public macro fun peel<$T>($data: vector<u8>, $peel_fn: |&mut BCS| -> $T): $T {
    let mut bcs = bcs::new($data);
    let result = $peel_fn(&mut bcs);
    assert!(bcs.into_remainder_bytes().length() == 0, error_remaining_data());
    result
}

public fun error_remaining_data(): u64 { ERemainingData }
