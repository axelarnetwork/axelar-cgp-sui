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
const EInvalidThreshold: u64 = 1;
/// For when operators have changed, and proof is no longer valid.
const EInvalidOperators: u64 = 2;

///-----
/// Macros
///-----
public(package) macro fun find(
    $s: &WeightedSigners,
    $f: |WeightedSigner| -> bool,
): Option<WeightedSigner> {
    // Bind $s to a local variable to avoid using macro parameter directly in a path expression which is not allowed
    let s = $s;
    let signers = s.signers();

    signers.find_index!($f).map!(|index| signers[index])
}

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

public(package) fun validate(self: &WeightedSigners) {
    let signers_length = self.signers().length();
    assert!(signers_length != 0, EInvalidOperators);

    let mut total_weight = 0;
    let mut previous_signer = weighted_signer::default();

    self.signers().do!<WeightedSigner>(|signer| {
        let weight = signer.weight();
        signer.validate(&previous_signer);
        total_weight = total_weight + weight;

        previous_signer = signer;
    });

    let threshold = self.threshold();

    assert!(threshold != 0 && total_weight >= threshold, EInvalidThreshold);
}

/// Finds the weight of a signer in the weighted signers.
public(package) fun find_signer_weight(signers: &WeightedSigners, pub_key: &vector<u8>): u128 {
    let signer = signers.find!(|signer| signer.pub_key() == pub_key);

    weighted_signer::parse_weight(signer)
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
