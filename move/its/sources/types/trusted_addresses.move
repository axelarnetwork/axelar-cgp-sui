module its::trusted_addresses;

const EMalformedTrustedAddresses: u64 = 0;

public struct TrustedAddresses has copy, drop {
    trusted_chains: vector<vector<u8>>,
    trusted_addresses: vector<vector<u8>>,
}

public fun new(trusted_chains: vector<vector<u8>>, trusted_addresses: vector<vector<u8>>): TrustedAddresses {
    let length = trusted_chains.length();

    assert!(length == trusted_addresses.length(), EMalformedTrustedAddresses);

    TrustedAddresses {
        trusted_chains,
        trusted_addresses,
    }
}

public fun destroy(
    self: TrustedAddresses,
): (vector<vector<u8>>, vector<vector<u8>>) {
    let TrustedAddresses { trusted_chains, trusted_addresses } = self;
    (trusted_chains, trusted_addresses)
}
