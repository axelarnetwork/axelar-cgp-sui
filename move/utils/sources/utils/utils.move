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
* Example Usage:
* ```move
* use axelar_gateway::proof;
* use utils::utils;
*
* let proof: Proof = utils::peel!(proof_data, |bcs| proof::peel(bcs));
* ```
*/
public macro fun peel<$T>($data: vector<u8>, $peel_fn: |&mut BCS| -> $T): $T {
    let mut bcs = bcs::new($data);
    let result = $peel_fn(&mut bcs);
    assert!(bcs.into_remainder_bytes().length() == 0, error_remaining_data());
    result
}

public fun error_remaining_data(): u64 { ERemainingData }

#[test]
fun test_peel_success() {
    let test_bytes = b"test";
    let data = bcs::to_bytes(&test_bytes);
    let peeled_data: vector<u8> = peel!(
        data,
        |bcs| bcs::peel_vec_u8(bcs),
    );
    assert!(peeled_data == test_bytes, 0);
}

#[test]
#[expected_failure(abort_code = ERemainingData)]
fun test_peel_error() {
    let data = b"ab";
    let _peeled: u8 = peel!(
        data,
        |bcs| bcs::peel_u8(bcs),
    );
}
