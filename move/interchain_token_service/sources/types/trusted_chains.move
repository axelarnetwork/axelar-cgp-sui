module interchain_token_service::trusted_chains {
    use interchain_token_service::events;
    use std::ascii::String;
    use sui::bag::{Self, Bag};

    // ------
    // Errors
    // ------
    #[error]
    const EEmptyChainName: vector<u8> = b"empty trusted chain name is unsupported";
    #[error]
    const EAlreadyTrusted: vector<u8> = b"chain is already trusted";
    #[error]
    const ENotTrusted: vector<u8> = b"chain is not trusted";

    public struct TrustedChain has drop, store {}

    /// The trusted chains where messages can be sent or received from.
    public struct TrustedChains has store {
        trusted_chains: Bag,
    }

    // -----------------
    // Package Functions
    // -----------------
    /// Create a new interchain address tracker.
    public(package) fun new(ctx: &mut TxContext): TrustedChains {
        TrustedChains {
            trusted_chains: bag::new(ctx),
        }
    }

    /// Check if the given address is trusted for the given chain.
    public(package) fun is_trusted(self: &TrustedChains, chain_name: String): bool {
        self.trusted_chains.contains(chain_name)
    }

    /// Set the trusted address for a chain or adds it if it doesn't exist.
    public(package) fun add(self: &mut TrustedChains, chain_name: String) {
        assert!(chain_name.length() > 0, EEmptyChainName);
        assert!(!self.trusted_chains.contains(chain_name), EAlreadyTrusted);

        self.trusted_chains.add(chain_name, TrustedChain {});
        events::trusted_chain_added(chain_name);
    }

    public(package) fun remove(self: &mut TrustedChains, chain_name: String) {
        assert!(chain_name.length() > 0, EEmptyChainName);
        assert!(self.trusted_chains.contains(chain_name), ENotTrusted);

        self.trusted_chains.remove<String, TrustedChain>(chain_name);
        events::trusted_chain_removed(chain_name);
    }

    // -----
    // Tests
    // -----
    #[test]
    fun test_trusted_chains() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let chain1 = std::ascii::string(b"chain1");
        let chain2 = std::ascii::string(b"chain2");

        self.add(chain1);
        self.add(chain2);

        assert!(self.is_trusted(chain1) == true);
        assert!(self.is_trusted(chain2) == true);

        assert!(self.trusted_chains.contains(chain1));
        assert!(self.trusted_chains.contains(chain2));

        self.remove(chain1);
        self.remove(chain2);

        assert!(self.is_trusted(chain1) == false);
        assert!(self.is_trusted(chain2) == false);

        assert!(!self.trusted_chains.contains(chain1));
        assert!(!self.trusted_chains.contains(chain2));

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EEmptyChainName)]
    fun test_add_trusted_chain_empty_chain_name() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let chain = std::ascii::string(b"");

        self.add(chain);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EAlreadyTrusted)]
    fun test_add_trusted_chain_already_trusted() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let chain = std::ascii::string(b"chain");

        self.add(chain);
        self.add(chain);

        sui::test_utils::destroy(self);
    }

    #[test]
    fun test_remove_trusted_chain() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let chain = std::ascii::string(b"chain");

        self.add(chain);
        self.remove(chain);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EEmptyChainName)]
    fun test_remove_trusted_chain_empty_chain_name() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let chain = std::ascii::string(b"");

        self.remove(chain);

        sui::test_utils::destroy(self);
    }
}
