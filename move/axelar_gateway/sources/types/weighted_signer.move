module axelar_gateway::weighted_signer {
    use sui::bcs::BCS;

    // ---------
    // Constants
    // ---------

    /// Length of a public key
    const PUBKEY_LENGTH: u64 = 33;

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
        assert!(pubkey.length() == PUBKEY_LENGTH, EInvalidPubkeyLength);

        WeightedSigner { pubkey, weight }
    }

    /// Empty weighted signer
    public(package) fun default(): WeightedSigner {
        let mut pubkey = @0x0.to_bytes();
        pubkey.push_back(0);

        WeightedSigner {
            pubkey,
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
        let mut i = 0;

        while (i < PUBKEY_LENGTH) {
            if (self.pubkey[i] < other.pubkey[i]) {
                return true
            } else if (self.pubkey[i] > other.pubkey[i]) {
                return false
            };

            i = i + 1;
        };

        false
    }

    // -----
    // Tests
    // -----

    #[test]
    fun test_default() {
        let signer = default();

        assert!(signer.weight == 0, 0);
        assert!(signer.pubkey.length() == PUBKEY_LENGTH, 1);

        let mut i = 0;
        while (i < PUBKEY_LENGTH) {
            assert!(signer.pubkey[i] == 0, 2);
            i = i + 1;
        }
    }
}
