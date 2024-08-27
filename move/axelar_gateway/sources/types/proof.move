module axelar_gateway::proof;

use axelar_gateway::weighted_signers::{Self, WeightedSigners};
use sui::bcs::BCS;
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

/// Recover the public key from an EVM recoverable signature, using keccak256 as the hash function
public(package) fun recover_pub_key(
    self: &Signature,
    message: &vector<u8>,
): vector<u8> {
    ecdsa::secp256k1_ecrecover(&self.bytes, message, 0)
}

public(package) fun peel_signature(bcs: &mut BCS): Signature {
    let bytes = bcs.peel_vec_u8();

    new_signature(bytes)
}

public(package) fun peel(bcs: &mut BCS): Proof {
    let signers = weighted_signers::peel(bcs);

    let mut signatures = vector::empty<Signature>();

    let mut length = bcs.peel_vec_length();

    while (length > 0) {
        signatures.push_back(peel_signature(bcs));

        length = length - 1;
    };

    Proof {
        signers,
        signatures,
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
