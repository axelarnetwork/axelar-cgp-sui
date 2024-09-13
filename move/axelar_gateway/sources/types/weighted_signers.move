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
const EInvalidSigners: u64 = 2;
const EMalformedSigners: u64 = 3;

///-----
/// Macros
///-----

/// Finds the first signer that satisfies the predicate.
/// The predicate is a function that takes a `WeightedSigner` as an argument and returns a boolean.
/// The function returns the first signer that satisfies the predicate and the index of the signer.
/// If no signer satisfies the predicate, the error `EMalformedSigners` is raised.
public(package) macro fun find(
    $s: &WeightedSigners,
    $index: u64,
    $f: |WeightedSigner| -> bool,
): (WeightedSigner, u64) {
    // Bind $s to a local variable to avoid using macro parameter directly in a path expression which is not allowed
    let s = $s;
    let signers = s.signers();
    let length = signers.length();
    let mut index = $index;

    // Find the first signer that satisfies the predicate
    while (index < length && !$f(signers[index])) {
        index = index + 1;
    };

    // If no signer satisfies the predicate, return an error
    assert!(index < length, EMalformedSigners);

    (signers[index], index)
}

/// -----------------
/// Package Functions
/// -----------------

/// Create a new weighted signers from the given data.
public(package) fun peel(bcs: &mut BCS): WeightedSigners {
    let len = bcs.peel_vec_length();
    assert!(len > 0, EInvalidLength);

    WeightedSigners {
        signers: vector::tabulate!(len, |_| weighted_signer::peel(bcs)),
        threshold: bcs.peel_u128(),
        nonce: bytes32::peel(bcs),
    }
}

/// Validates the weighted signers. The following must be true:
/// 1. The signers are in ascending order by their public key.
/// 2. The threshold is greater than zero.
/// 3. The threshold is less than or equal to the total weight of the signers.
public(package) fun validate(self: &WeightedSigners) {
    assert!(!self.signers.is_empty(), EInvalidSigners);

    validate_signers_order(self.signers);
    let total_weight = calculate_total_weight(self.signers);
    validate_threshold(self.threshold(), total_weight);
}

/// Finds the weight of a signer in the weighted signers by its public key.
public(package) fun find_signer_weight(
    self: &WeightedSigners,
    signer_index: u64,
    pub_key: &vector<u8>,
): (u128, u64) {
    // Find the signer by its public key
    // The index of the signer is returned as well for reuse in the macro call
    let (signer, index) = self.find!(signer_index, |signer| signer.pub_key() == pub_key);

    (weighted_signer::parse_weight(&signer), index)
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

/// -----
/// Internal Functions
/// -----

/// Validates the order of the signers.
/// The signers must be in ascending order by their public key.
/// Otherwise, the error `EInvalidSigners` is raised.
fun validate_signers_order(signers: vector<WeightedSigner>) {
    let mut previous = weighted_signer::default();
    signers.do!(
        |signer| {
            signer.validate(&previous);
            previous = signer;
        },
    );
}

/// Calculates the total weight of the signers.
fun calculate_total_weight(signers: vector<WeightedSigner>): u128 {
    signers.fold!<WeightedSigner, u128>(
        0,
        |acc, signer| acc + signer.weight(),
    )
}

/// Validates the threshold.
/// The threshold must be greater than zero and less than or equal to the total weight of the signers.
/// Otherwise, the error `EInvalidThreshold` is raised.
fun validate_threshold(threshold: u128, total_weight: u128) {
    assert!(threshold != 0 && total_weight >= threshold, EInvalidThreshold);
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
