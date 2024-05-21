module axelar_gateway::proof {
    use sui::bcs::BCS;

    use axelar_gateway::weighted_signers::{Self, WeightedSigners};

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

    // -----------------
    // Package Functions
    // -----------------
    public(package) fun peel_signature(bcs: &mut BCS): Signature {
        let bytes = bcs.peel_vec_u8();
        assert!(bytes.length() == SIGNATURE_LENGTH, EInvalidLength);

        Signature {
            bytes: bytes,
        }
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
}
