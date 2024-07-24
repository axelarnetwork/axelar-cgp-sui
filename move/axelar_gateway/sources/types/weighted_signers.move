module axelar_gateway::weighted_signers {
    use sui::bcs::{Self, BCS};
    use sui::hash;

    use axelar_gateway::bytes32::{Self, Bytes32};
    use axelar_gateway::weighted_signer::{Self, WeightedSigner};

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

    /// ----------------
    /// Public Functions
    /// ----------------
    public(package) fun signers(self: &WeightedSigners): vector<WeightedSigner> {
        self.signers
    }

    public(package) fun threshold(self: &WeightedSigners): u128 {
        self.threshold
    }

    public(package) fun nonce(self: &WeightedSigners): Bytes32 {
        self.nonce
    }

    /// -----------------
    /// Package Functions
    /// -----------------
    public(package) fun peel(bcs: &mut BCS): WeightedSigners {
        let mut signers = vector::empty<WeightedSigner>();

        let mut length = bcs.peel_vec_length();
        assert!(length > 0, EInvalidLength);

        while (length > 0) {
            signers.push_back(weighted_signer::peel(bcs));

            length = length - 1;
        };

        let threshold = bcs.peel_u128();
        let nonce = bytes32::peel(bcs);

        WeightedSigners {
            signers,
            threshold,
            nonce,
        }
    }

    public(package) fun hash(self: &WeightedSigners): Bytes32 {
        bytes32::from_bytes(hash::keccak256(&bcs::to_bytes(self)))
    }

    #[test_only]
    public fun new_for_testing(
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
}
