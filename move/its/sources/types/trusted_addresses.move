module its::trusted_addresses;

use std::ascii::String;

/// ------
/// Errors
/// ------
#[error]
const EMalformedTrustedAddresses: vector<u8> =
    b"trusted chains and addresses have mismatching length";

/// -----
/// Types
/// -----
public struct TrustedAddresses has copy, drop {
    trusted_chains: vector<String>,
    trusted_addresses: vector<String>,
}

/// ----------------
/// Public Functions
/// ----------------
public fun new(
    trusted_chains: vector<String>,
    trusted_addresses: vector<String>,
): TrustedAddresses {
    let length = trusted_chains.length();

    assert!(length == trusted_addresses.length(), EMalformedTrustedAddresses);

    TrustedAddresses {
        trusted_chains,
        trusted_addresses,
    }
}

/// -----------------
/// Package Functions
/// -----------------
public(package) fun destroy(self: TrustedAddresses): (vector<String>, vector<String>) {
    let TrustedAddresses { trusted_chains, trusted_addresses } = self;
    (trusted_chains, trusted_addresses)
}

/// ---------
/// Test Only
/// ---------
// This does not preform sanity checks on the params
#[test_only]
public(package) fun new_for_testing(
    trusted_chains: vector<String>,
    trusted_addresses: vector<String>,
): TrustedAddresses {
    TrustedAddresses {
        trusted_chains,
        trusted_addresses,
    }
}

/// ----
/// Test
/// ----
#[test]
#[expected_failure(abort_code = EMalformedTrustedAddresses)]
fun test_new_malformed() {
    new(vector[], vector[b"address".to_ascii_string()]);
}
