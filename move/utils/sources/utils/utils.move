/// Module: utils
module utils::utils;

use sui::bcs::{Self, BCS};

// -----
// Macros
// -----

/**
* Peel data from a BCS encoded vector
* @dev This macro is used to peel data from a BCS encoded vector
* The macro will assert that there is no remaining data in the BCS after peelin. If there is remaining data, the macro will panic.
* @param $data The BCS encoded vector
* @param $peel_fn The function to peel the data
* @returns The peeled data or an error if there is any remaining data in the BCS
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
    assert!(bcs.into_remainder_bytes().length() == 0);
    result
}


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
#[expected_failure]
fun test_peel_error() {
    let data = b"ab";
    let _peeled: u8 = peel!(
        data,
        |bcs| bcs::peel_u8(bcs),
    );
}
