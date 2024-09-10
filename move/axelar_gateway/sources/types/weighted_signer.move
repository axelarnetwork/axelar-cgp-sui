module axelar_gateway::weighted_signer;

use sui::bcs::BCS;

// ---------
// Constants
// ---------

/// Length of a public key
const PUB_KEY_LENGTH: u64 = 33;

// -----
// Types
// -----

public struct WeightedSigner has copy, drop, store {
    pub_key: vector<u8>,
    weight: u128,
}

public fun pub_key(self: &WeightedSigner): vector<u8> {
    self.pub_key
}

public fun weight(self: &WeightedSigner): u128 {
    self.weight
}

// ------
// Errors
// ------

const EInvalidPubKeyLength: u64 = 0;

// -----------------
// Package Functions
// -----------------

public(package) fun new(pub_key: vector<u8>, weight: u128): WeightedSigner {
    assert!(pub_key.length() == PUB_KEY_LENGTH, EInvalidPubKeyLength);

    WeightedSigner { pub_key, weight }
}

/// Empty weighted signer
public(package) fun default(): WeightedSigner {
    let mut pub_key = @0x0.to_bytes();
    pub_key.push_back(0);

    WeightedSigner {
        pub_key,
        weight: 0,
    }
}

public(package) fun peel(bcs: &mut BCS): WeightedSigner {
    let pub_key = bcs.peel_vec_u8();
    let weight = bcs.peel_u128();

    new(pub_key, weight)
}

/// Check if self.signer is less than other.signer as bytes
public(package) fun lt(self: &WeightedSigner, other: &WeightedSigner): bool {
    let mut i = 0;

    while (i < PUB_KEY_LENGTH) {
        if (self.pub_key[i] < other.pub_key[i]) {
            return true
        } else if (self.pub_key[i] > other.pub_key[i]) {
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
    assert!(signer.pub_key.length() == PUB_KEY_LENGTH, 1);

    let mut i = 0;
    while (i < PUB_KEY_LENGTH) {
        assert!(signer.pub_key[i] == 0, 2);
        i = i + 1;
    }
}

#[test]
fun test_lt() {
    let signer1 = new(
        x"000100000000000000000000000000000000000000000000000000000000000000",
        1,
    );
    let signer2 = new(
        x"000200000000000000000000000000000000000000000000000000000000000000",
        2,
    );
    let signer3 = new(
        x"000100000000000000000000000000000000000000000000000000000000000001",
        3,
    );

    // Less than
    assert!(lt(&signer1, &signer2), 0);
    assert!(lt(&signer1, &signer3), 2);

    // Not less than
    assert!(!lt(&signer2, &signer1), 1);
    assert!(!lt(&signer3, &signer1), 3);

    // Equal
    assert!(!lt(&signer1, &signer1), 4); // !(signer1 < signer1)
}
