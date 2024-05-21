module axelar_gateway::weighted_signers {
    use sui::bcs::BCS;

    use axelar_gateway::bytes32::{Self, Bytes32};
    use axelar_gateway::weighted_signer::{Self};

    public struct WeightedSigners has copy, drop, store {
        signers: vector<weighted_signer::WeightedSigner>,
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
        let mut signers = vector::empty<weighted_signer::WeightedSigner>();

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
}
