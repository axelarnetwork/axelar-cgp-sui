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
#[error]
const EInvalidSignersLength: vector<u8> = b"invalid signers length: expected at least 1 signer";

#[error]
const EInvalidThreshold: vector<u8> = b"invalid threshold: expected non-zero value and less than or equal to the total weight of the signers";

#[error]
const EInvalidSignerOrder: vector<u8> = b"invalid signer order: signers must be in ascending order by their public key";

/// -----------------
/// Package Functions
/// -----------------

/// Decode a `WeightedSigners` from the BCS encoded bytes.
public(package) fun peel(bcs: &mut BCS): WeightedSigners {
    let len = bcs.peel_vec_length();
    assert!(len > 0, EInvalidSignersLength);

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
    self.validate_signers();
    self.validate_threshold();
}

public(package) fun hash(self: &WeightedSigners): Bytes32 {
    bytes32::from_bytes(hash::keccak256(&bcs::to_bytes(self)))
}

public(package) fun signers(self: &WeightedSigners): &vector<WeightedSigner> {
    &self.signers
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

/// Validates the order of the signers and the length of the signers.
/// The signers must be in ascending order by their public key.
/// Otherwise, the error `EInvalidSignersLength` is raised.
fun validate_signers(self: &WeightedSigners) {
    assert!(!self.signers.is_empty(), EInvalidSignersLength);
    let mut previous = &weighted_signer::default();
    self.signers.do_ref!(
        |signer| {
            signer.validate();
            assert!(previous.lt(signer), EInvalidSignerOrder);
            previous = signer;
        },
    );
}

/// Calculates the total weight of the signers.
fun total_weight(self: &WeightedSigners): u128 {
    self.signers.fold!<WeightedSigner, u128>(
        0,
        |acc, signer| acc + signer.weight(),
    )
}

/// Validates the threshold.
/// The threshold must be greater than zero and less than or equal to the total weight of the signers.
/// Otherwise, the error `EInvalidThreshold` is raised.
fun validate_threshold(self: &WeightedSigners) {
    assert!(self.threshold != 0 && self.total_weight() >= self.threshold, EInvalidThreshold);
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


#[test]
fun tent_nonce() {
    let weighted_signers = dummy();
    assert!(weighted_signers.nonce() == bytes32::new(@3456));
}

#[test]
#[expected_failure(abort_code = EInvalidSignersLength)]
fun test_peel_invalid_signers_length() {
    let mut bcs = bcs::new(
        bcs::to_bytes(
            &WeightedSigners {
                signers: vector[],
                threshold: 0,
                nonce: bytes32::new(@0x0),
            }
        )
    );
    peel(&mut bcs);
}

#[test]
#[expected_failure(abort_code = EInvalidSignersLength)]
fun test_validate_signers_invalid_signers_length() {
    WeightedSigners {
        signers: vector[],
        threshold: 0,
        nonce: bytes32::new(@0x0),
    }.validate_signers();
}

#[test]
#[expected_failure(abort_code = EInvalidSignerOrder)]
fun test_validate_signers_invalid_signer_order() {
    let mut pub_key = @0x0.to_bytes();
    pub_key.push_back(2);
    let signer1 = axelar_gateway::weighted_signer::new(pub_key, 1);
    pub_key = @0x0.to_bytes();
    pub_key.push_back(1);
    let signer2 = axelar_gateway::weighted_signer::new(pub_key, 1);
    WeightedSigners {
        signers: vector[signer1, signer2],
        threshold: 1,
        nonce: bytes32::new(@0x0),
    }.validate_signers();
}

#[test]
#[expected_failure(abort_code = EInvalidThreshold)]
fun test_validate_zero_threshold() {
    WeightedSigners {
        signers: vector[],
        threshold: 0,
        nonce: bytes32::new(@0x0),
    }.validate_threshold();
}

#[test]
#[expected_failure(abort_code = EInvalidThreshold)]
fun test_validate_threshold_above_weight_sum() {
    let mut pub_key = @0x0.to_bytes();
    pub_key.push_back(2);
    let signer = axelar_gateway::weighted_signer::new(pub_key, 0);
    WeightedSigners {
        signers: vector[signer],
        threshold: 2,
        nonce: bytes32::new(@0x0),
    }.validate_threshold();
}
