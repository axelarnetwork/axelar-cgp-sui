module axelar_gateway::weighted_signers;

use axelar_gateway::bytes32::{Self, Bytes32};
use axelar_gateway::weighted_signer::{Self, WeightedSigner};
use sui::bcs::{Self, BCS};
use sui::hash;

public struct WeightedSigners has copy, drop, store {
    signers: vector<WeightedSigner>,
    threshold: u128,
    nonce: Bytes32,
}

/// ------
/// Errors
/// ------
/// Invalid length of the bytes
const EInvalidLength: u64 = 0;

/// -----------------
/// Package Functions
/// -----------------
public(package) fun peel(bcs: &mut BCS): WeightedSigners {
    let len = bcs.peel_vec_length();
    assert!(len > 0, EInvalidLength);

    WeightedSigners {
        signers: vector::tabulate!(len, |_| weighted_signer::peel(bcs)),
        threshold: bcs.peel_u128(),
        nonce: bytes32::peel(bcs)
    }
}

public(package) fun hash(self: &WeightedSigners): Bytes32 {
    bytes32::from_bytes(hash::keccak256(&bcs::to_bytes(self)))
}

public(package) fun signers(self: &WeightedSigners): vector<WeightedSigner> {
    self.signers
}

public(package) fun threshold(self: &WeightedSigners): u128 {
    self.threshold
}

public(package) fun nonce(self: &WeightedSigners): Bytes32 {
    self.nonce
}

public(package) macro fun find($s: &WeightedSigners, $f: |WeightedSigner| -> bool): Option<WeightedSigner> {
    let s = $s;  // Bind $s to a local variable to avoid using macro parameter directly in a path expression which is not allowed
    let signers = s.signers();
    let mut signer_option = signers.find_index!($f);

    if (signer_option.is_none()) {
        return option::none()
    };

    let signer_index = signer_option.extract();
    let signer = signers[signer_index];

    option::some(signer)
}

#[test_only]
public fun create_for_testing(
    signers: vector<WeightedSigner>,
    threshold: u128,
    nonce: Bytes32,
): WeightedSigners {
    WeightedSigners {
        signers,
        threshold,
        nonce,
    }
}

#[test_only]
public fun dummy(): WeightedSigners {
    let pub_key = vector[
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
        29,
        30,
        31,
        32,
    ];
    let signer = axelar_gateway::weighted_signer::new(pub_key, 123);
    let nonce = bytes32::new(@3456);
    let threshold = 100;
    WeightedSigners {
        signers: vector[signer],
        threshold,
        nonce,
    }
}
