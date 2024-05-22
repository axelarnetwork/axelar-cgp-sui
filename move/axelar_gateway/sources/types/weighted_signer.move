module axelar_gateway::weighted_signer {
    use sui::bcs::BCS;

    // -----
    // Types
    // -----
    public struct WeightedSigner has copy, drop, store {
        pubkey: vector<u8>,
        weight: u128,
    }

    public fun pubkey(self: &WeightedSigner): vector<u8> {
        self.pubkey
    }

    public fun weight(self: &WeightedSigner): u128 {
        self.weight
    }

    // ------
    // Errors
    // ------
    const EInvalidPubkeyLength: u64 = 0;

    // -----------------
    // Package Functions
    // -----------------
    public(package) fun new(pubkey: vector<u8>, weight: u128): WeightedSigner {
        assert!(pubkey.length() == 33, EInvalidPubkeyLength);

        WeightedSigner { pubkey, weight }
    }

    /// zero pubkey
    public(package) fun default(): WeightedSigner {
        WeightedSigner {
            pubkey: vector[],
            weight: 0,
        }
    }

    public(package) fun peel(bcs: &mut BCS): WeightedSigner {
        let pubkey = bcs.peel_vec_u8();
        let weight = bcs.peel_u128();

        new(pubkey, weight)
    }

    /// Check if self.signer is less than other.signer as bytes
    public(package) fun lt(self: &WeightedSigner, other: &WeightedSigner): bool {
        let length = 33;
        let mut i = 0;

        while (i < length) {
            if (self.pubkey[i] < other.pubkey[i]) {
                return true
            } else if (self.pubkey[i] > other.pubkey[i]) {
                return false
            };

            i = i + 1;
        };

        false
    }
}
