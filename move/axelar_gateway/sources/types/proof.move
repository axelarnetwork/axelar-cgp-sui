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
#[error]
const EInvalidSignatureLength: vector<u8> =
    b"invalid signature length: expected 65 bytes";

#[error]
const ELowSignaturesWeight: vector<u8> = b"insufficient signatures weight";

#[error]
const ESignerNotFound: vector<u8> =
    b"no signer found with the specified public key in the given range";

#[error]
const ERedundantSignaturesProvided: vector<u8> =
    b"redundant signatures provided";

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
    assert!(bytes.length() == SIGNATURE_LENGTH, EInvalidSignatureLength);

    Signature {
        bytes: bytes,
    }
}

/// Recover the public key from an EVM recoverable signature, using keccak256 as
/// the hash function
public(package) fun recover_pub_key(
    self: &Signature,
    message: &vector<u8>,
): vector<u8> {
    ecdsa::secp256k1_ecrecover(&self.bytes, message, 0)
}

/// Validates the signatures of a message against the signers.
/// The total weight of the signatures must be greater than or equal to the
/// threshold.
/// Otherwise, the error `ELowSignaturesWeight` is raised.
public(package) fun validate(self: &Proof, message: vector<u8>) {
    let signers = &self.signers;
    let signatures = &self.signatures;
    assert!(signatures.length() != 0, ELowSignaturesWeight);

    let threshold = signers.threshold();
    let signatures_length = signatures.length();
    let mut total_weight: u128 = 0;
    let mut signer_index = 0;
    let mut i = 0;

    while (i < signatures_length) {
        let pub_key = signatures[i].recover_pub_key(&message);

        let (weight, index) = find_weight_by_pub_key_from(
            signers,
            signer_index,
            &pub_key,
        );

        total_weight = total_weight + weight;

        if (total_weight >= threshold) {
            if (i + 1 == signatures_length) {
                return
            };

            abort ERedundantSignaturesProvided
        };

        i = i + 1;
        signer_index = index + 1;
    };

    abort ELowSignaturesWeight
}

/// Finds the weight of a signer in the weighted signers by its public key.
fun find_weight_by_pub_key_from(
    signers: &WeightedSigners,
    signer_index: u64,
    pub_key: &vector<u8>,
): (u128, u64) {
    let signers = signers.signers();
    let length = signers.length();
    let mut index = signer_index;

    // Find the first signer that satisfies the predicate
    while (index < length && signers[index].pub_key() != pub_key) {
        index = index + 1;
    };

    // If no signer satisfies the predicate, return an error
    assert!(index < length, ESignerNotFound);

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

// ---------
// Test Only
// ---------
#[test_only]
public(package) fun create_for_testing(
    signers: WeightedSigners,
    signatures: vector<Signature>,
): Proof {
    Proof {
        signers,
        signatures,
    }
}

#[test_only]
public(package) fun dummy(): Proof {
    let mut signature = sui::address::to_bytes(@0x01);
    signature.append(sui::address::to_bytes(@0x23));
    signature.push_back(2);
    Proof {
        signers: axelar_gateway::weighted_signers::dummy(),
        signatures: vector[Signature { bytes: signature }],
    }
}

#[test_only]
public(package) fun generate(
    weighted_signers: WeightedSigners,
    message_to_sign: &vector<u8>,
    keypairs: &vector<ecdsa::KeyPair>,
): Proof {
    let signatures = keypairs.map_ref!(
        |keypair| new_signature(
            ecdsa::secp256k1_sign(
                keypair.private_key(),
                message_to_sign,
                0,
                true,
            ),
        ),
    );
    create_for_testing(weighted_signers, signatures)
}

// -----
// Tests
// -----
#[test]
fun test_getters() {
    let proof = dummy();

    assert!(proof.signers() == axelar_gateway::weighted_signers::dummy());

    let mut signature = sui::address::to_bytes(@0x01);
    signature.append(sui::address::to_bytes(@0x23));
    signature.push_back(2);
    assert!(proof.signatures() == vector[Signature { bytes: signature }]);
}

#[test]
#[expected_failure(abort_code = EInvalidSignatureLength)]
fun test_new_signature_invalid_signature_length() {
    new_signature(vector[]);
}

#[test]
fun test_recover_pub_key() {
    let keypair = ecdsa::secp256k1_keypair_from_seed(&@0x1234.to_bytes());
    let message = @0x5678.to_bytes();
    let signature = new_signature(
        ecdsa::secp256k1_sign(keypair.private_key(), &message, 0, true),
    );
    assert!(signature.recover_pub_key(&message) == keypair.public_key());
}

#[test]
fun test_validate() {
    let mut keypairs = vector[@0x1234, @0x5678, @0x9abc].map!(
        |seed| ecdsa::secp256k1_keypair_from_seed(&seed.to_bytes()),
    );
    let pub_keys = keypairs.map_ref!(|keypair| *keypair.public_key());
    let weights = vector[123, 234, 456];
    let message = @0x5678.to_bytes();
    let nonce = axelar_gateway::bytes32::new(@0x0123);

    let weighted_signers = axelar_gateway::weighted_signers::create_for_testing(
        vector[0, 1, 2].map!(
            |index| axelar_gateway::weighted_signer::new(
                pub_keys[index],
                weights[index],
            ),
        ),
        weights[0] + weights[2],
        nonce,
    );
    keypairs.remove(1);
    let proof = generate(weighted_signers, &message, &keypairs);
    proof.validate(message);
}

#[test]
#[expected_failure(abort_code = ERedundantSignaturesProvided)]
fun test_validate_redundant_signatures() {
    let keypairs = vector[@0x1234, @0x5678, @0x9abc].map!(
        |seed| ecdsa::secp256k1_keypair_from_seed(&seed.to_bytes()),
    );
    let pub_keys = keypairs.map_ref!(|keypair| *keypair.public_key());
    let weights = vector[123, 234, 456];
    let message = @0x5678.to_bytes();
    let nonce = axelar_gateway::bytes32::new(@0x0123);

    let weighted_signers = axelar_gateway::weighted_signers::create_for_testing(
        vector[0, 1, 2].map!(
            |index| axelar_gateway::weighted_signer::new(
                pub_keys[index],
                weights[index],
            ),
        ),
        weights[0] + weights[1],
        nonce,
    );
    let proof = generate(weighted_signers, &message, &keypairs);
    proof.validate(message);
}

#[test]
#[expected_failure(abort_code = ELowSignaturesWeight)]
fun test_validate_empty_signers() {
    let message = @0x5678.to_bytes();
    let nonce = axelar_gateway::bytes32::new(@0x0123);
    let weighted_signers = axelar_gateway::weighted_signers::create_for_testing(
        vector[],
        1,
        nonce,
    );
    let proof = create_for_testing(weighted_signers, vector[]);
    proof.validate(message);
}

#[test]
#[expected_failure(abort_code = ELowSignaturesWeight)]
fun test_validate_low_signature_weight() {
    let keypairs = vector[@0x1234, @0x5678, @0x9abc].map!(
        |seed| ecdsa::secp256k1_keypair_from_seed(&seed.to_bytes()),
    );
    let pub_keys = keypairs.map_ref!(|keypair| *keypair.public_key());
    let weights = vector[123, 234, 456];
    let message = @0x5678.to_bytes();
    let nonce = axelar_gateway::bytes32::new(@0x0123);

    let weighted_signers = axelar_gateway::weighted_signers::create_for_testing(
        vector[0, 1, 2].map!(
            |index| axelar_gateway::weighted_signer::new(
                pub_keys[index],
                weights[index],
            ),
        ),
        weights[0] + weights[2] + 1,
        nonce,
    );
    let signatures = keypairs.map!(
        |keypair| new_signature(
            ecdsa::secp256k1_sign(keypair.private_key(), &message, 0, true),
        ),
    );
    let proof = create_for_testing(
        weighted_signers,
        vector[signatures[0], signatures[2]],
    );
    proof.validate(message);
}

#[test]
#[expected_failure(abort_code = ESignerNotFound)]
fun test_validate_signer_not_found() {
    let keypairs = vector[@0x1234, @0x5678, @0x9abc].map!(
        |seed| ecdsa::secp256k1_keypair_from_seed(&seed.to_bytes()),
    );
    let pub_keys = keypairs.map_ref!(|keypair| *keypair.public_key());
    let weights = vector[123, 234, 456];
    let message = @0x5678.to_bytes();
    let nonce = axelar_gateway::bytes32::new(@0x0123);

    let weighted_signers = axelar_gateway::weighted_signers::create_for_testing(
        vector[0, 2].map!(
            |index| axelar_gateway::weighted_signer::new(
                pub_keys[index],
                weights[index],
            ),
        ),
        weights[0] + weights[2],
        nonce,
    );
    let signatures = keypairs.map!(
        |keypair| new_signature(
            ecdsa::secp256k1_sign(keypair.private_key(), &message, 0, true),
        ),
    );
    let proof = create_for_testing(weighted_signers, vector[signatures[1]]);
    proof.validate(message);
}
