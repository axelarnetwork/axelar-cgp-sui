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
const EInvalidOperators: u64 = 1;
const EInvalidWeights: u64 = 2;
const EMalformedSigners: u64 = 3;

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

public(package) fun validate(self: &WeightedSigner, previous_signer: &WeightedSigner) {
    assert!(previous_signer.lt(self), EInvalidOperators);

    let weight = self.weight();

    assert!(weight != 0, EInvalidWeights);
}

/// Extracts the weight from the option and asserts that it is not zero.
public(package) fun parse_weight(signer: Option<WeightedSigner>): u128 {
    let mut weight = signer.map!(|signer| signer.weight());
    assert!(weight.is_some(), EMalformedSigners);
    let value = weight.extract();
    assert!(value != 0, EInvalidWeights);

    value
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
fun verify_default_signer() {
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
fun compare_weight_signers() {
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
    assert!(signer1.lt(&signer2), 0);
    assert!(signer1.lt(&signer3), 2);

    // Not less than
    assert!(!signer2.lt(&signer1), 1);
    assert!(!signer3.lt(&signer1), 3);

    // Equal
    assert!(!signer1.lt(&signer1), 4); // !(signer1 < signer1)
}
