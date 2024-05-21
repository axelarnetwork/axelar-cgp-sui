module axelar_gateway::weighted_signer {
    use sui::bcs::BCS;

    /// -----
    /// Types
    /// -----
    public struct WeightedSigner has copy, drop, store {
        signer: vector<u8>,
        weight: u128,
    }

    public fun pubkey(self: &WeightedSigner): vector<u8> {
        self.signer
    }

    public fun weight(self: &WeightedSigner): u128 {
        self.weight
    }

    /// -----------------
    /// Package Functions
    /// -----------------
    public(package) fun peel(bcs: &mut BCS): WeightedSigner {
        let signer = bcs.peel_vec_u8();
        let weight = bcs.peel_u128();

        WeightedSigner { signer, weight }
    }
}
