module its::trusted_addresses;

use std::ascii::String;

const EMalformedTrustedAddresses: u64 = 0;

public struct TrustedAddresses has copy, drop {
    trusted_chains: vector<String>,
    trusted_addresses: vector<String>,
}

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

public fun destroy(self: TrustedAddresses): (vector<String>, vector<String>) {
    let TrustedAddresses { trusted_chains, trusted_addresses } = self;
    (trusted_chains, trusted_addresses)
}
