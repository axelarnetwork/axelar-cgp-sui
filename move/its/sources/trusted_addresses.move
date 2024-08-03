module its::trusted_addresses {
    use sui::bcs::BCS;

    const EMalformedTrustedAddresses: u64 = 0;

    public struct TrustedAddresses has copy, drop {
        trusted_chains: vector<vector<u8>>,
        trusted_addresses: vector<vector<u8>>,
    }

    public fun peel(bcs: &mut BCS): TrustedAddresses {
        let trusted_chains = bcs.peel_vec_vec_u8();
        let trusted_addresses = bcs.peel_vec_vec_u8();
        
        let length = trusted_chains.length();

        assert!(length == trusted_addresses.length(), EMalformedTrustedAddresses);

        TrustedAddresses {
            trusted_chains,
            trusted_addresses,
        }
    }

    public fun destroy(self: TrustedAddresses): (vector<vector<u8>>, vector<vector<u8>>) {
        let TrustedAddresses { trusted_chains, trusted_addresses } = self;
        (trusted_chains, trusted_addresses)
    }

    #[test_only]
    public fun new_for_testing(trusted_chains: vector<vector<u8>>, trusted_addresses: vector<vector<u8>>): TrustedAddresses {
        TrustedAddresses {
            trusted_chains,
            trusted_addresses,
        }
    }
}