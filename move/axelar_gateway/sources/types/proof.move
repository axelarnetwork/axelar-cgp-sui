module axelar_gateway::proof;

use axelar_gateway::weighted_signers::{Self, WeightedSigners};
use axelar_gateway::bytes32::{Bytes32};
use sui::bcs::{Self, BCS};
use sui::ecdsa_k1 as ecdsa;

// -----
// Types
// -----
public struct Signature has copy, drop, store {
    bytes: vector<u8>,
}

public struct Proof has copy, drop, store {
    signers: WeightedSigners,
    signatures: vector<Signature>,
}

public struct MessageToSign has copy, drop, store {
    domain_separator: Bytes32,
    signers_hash: Bytes32,
    data_hash: Bytes32,
}
// ---------
// Constants
// ---------
/// Length of the signature
const SIGNATURE_LENGTH: u64 = 65;

// ------
// Errors
// ------
/// Invalid length of the bytes
const EInvalidLength: u64 = 0;
const ELowSignaturesWeight: u64 = 1;
const EMalformedSigners: u64 = 2;

// ----------------
// Public Functions
// ----------------
/// The signers of the proof
public fun signers(proof: &Proof): &WeightedSigners {
    &proof.signers
}

/// The proof signatures
public fun signatures(proof: &Proof): &vector<Signature> {
    &proof.signatures
}

// -----------------
// Package Functions
// -----------------
public(package) fun new_signature(bytes: vector<u8>): Signature {
    assert!(bytes.length() == SIGNATURE_LENGTH, EInvalidLength);

    Signature {
        bytes: bytes,
    }
}

public(package) fun new_message_to_sign(
    domain_separator: Bytes32,
    signers_hash: Bytes32,
    data_hash: Bytes32,
): MessageToSign {
    MessageToSign {
        domain_separator,
        signers_hash,
        data_hash,
    }
}

/// Recover the public key from an EVM recoverable signature, using keccak256 as the hash function
public(package) fun recover_pub_key(
    self: &Signature,
    message: &vector<u8>,
): vector<u8> {
    ecdsa::secp256k1_ecrecover(&self.bytes, message, 0)
}

/// Validates the signatures of a message against the signers.
/// The total weight of the signatures must be greater than or equal to the threshold.
/// Otherwise, the error `ELowSignaturesWeight` is raised.
public(package) fun validate(
    self: &Proof,
    message: MessageToSign,
) {
    let signers = self.signers();
    let signatures = self.signatures();
    assert!(signatures.length() != 0, ELowSignaturesWeight);

    let threshold = signers.threshold();
    let mut total_weight: u128 = 0;
    let mut signer_index = 0;
    let mut i = 0;
    let message_bytes = bcs::to_bytes(&message);

    while(i < signatures.length()) {
        let signature = signatures[i];

        let pub_key = signature.recover_pub_key(&message_bytes);

        let (weight, index) = find_weight_by_pub_key_from(signers, signer_index, &pub_key);

        signer_index = index;

        total_weight = total_weight + weight;

        i = i + 1;

        if (total_weight >= threshold) return
    };

    assert!(total_weight >= threshold, ELowSignaturesWeight);
}

/// Finds the weight of a signer in the weighted signers by its public key.
public(package) fun find_weight_by_pub_key_from(
    weight_signers: &WeightedSigners,
    signer_index: u64,
    pub_key: &vector<u8>,
): (u128, u64) {
    let signers = weight_signers.signers();
    let length = signers.length();
    let mut index = signer_index;

    // Find the first signer that satisfies the predicate
    while (index < length && signers[index].pub_key() != pub_key) {
        index = index + 1;
    };

    // If no signer satisfies the predicate, return an error
    assert!(index < length, EMalformedSigners);

    (signers[index].weight(), index)
}

public(package) fun peel_signature(bcs: &mut BCS): Signature {
    let bytes = bcs.peel_vec_u8();

    new_signature(bytes)
}

public(package) fun peel(bcs: &mut BCS): Proof {
    let signers = weighted_signers::peel(bcs);
    let length = bcs.peel_vec_length();

    Proof {
        signers,
        signatures: vector::tabulate!(length, |_| peel_signature(bcs)),
    }
}

#[test_only]
public fun create_for_testing(
    signers: WeightedSigners,
    signatures: vector<Signature>,
): Proof {
    Proof {
        signers,
        signatures,
    }
}

#[test_only]
public fun dummy(): Proof {
    let mut signature = sui::address::to_bytes(@0x01);
    signature.append(sui::address::to_bytes(@0x23));
    signature.push_back(2);
    Proof {
        signers: axelar_gateway::weighted_signers::dummy(),
        signatures: vector[Signature { bytes: signature }],
    }
}
