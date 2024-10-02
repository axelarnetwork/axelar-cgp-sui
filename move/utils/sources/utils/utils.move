/// Module: utils
module utils::utils;

use sui::bcs::{Self, BCS};

// -----
// Macros
// -----

/// Peel data from a BCS encoded vector
/// This macro is used to peel data from a BCS encoded vector
/// The macro will assert that there is no remaining data in the BCS after peeling. If there is
/// remaining data, the macro will panic.
/// $data: The BCS encoded vector
/// $peel_fn: The function to peel the data
/// Returns: The peeled data or an error if there is any remaining data in the BCS
///
/// Example Usage:
/// ```
/// use axelar_gateway::proof;
/// use utils::utils;
///
/// let proof: Proof = utils::peel!(proof_data, |bcs| proof::peel(bcs));
/// ```
public macro fun peel<$T>($data: vector<u8>, $peel_fn: |&mut BCS| -> $T): $T {
    let mut bcs = bcs::new($data);
    let result = $peel_fn(&mut bcs);
    assert!(bcs.into_remainder_bytes().length() == 0);
    result
}

#[test]
fun peel_bcs_data_succeeds() {
    let test_bytes = b"test";
    let data = bcs::to_bytes(&test_bytes);
    let peeled_data: vector<u8> = peel!(data, |bcs| bcs::peel_vec_u8(bcs));
    assert!(peeled_data == test_bytes);
}

#[test]
#[expected_failure]
fun peel_bcs_data_fails_when_data_remains() {
    let data = b"ab";
    let _peeled: u8 = peel!(data, |bcs| bcs::peel_u8(bcs));
}
