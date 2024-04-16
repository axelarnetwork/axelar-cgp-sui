/// Q: why addresses are stored as Strings?
/// Q: why chains are Strings?
module its::address_tracker {
    use std::ascii::{String};

    use sui::table::{Self, Table};

    /// Attempt to borrow a trusted address but it's not registered.
    const ENoAddress: u64 = 0;

    /// The interchain address tracker stores the trusted addresses for each chain.
    public struct InterchainAddressTracker has store {
        trusted_addresses: Table<String, String>
    }

    /// Get the trusted address for a chain.
    public fun get_trusted_address(
        self: &InterchainAddressTracker, chain_name: String
    ): &String {
        assert!(self.trusted_addresses.contains(chain_name), ENoAddress);
        self.trusted_addresses.borrow(chain_name)
    }

    /// Check if the given address is trusted for the given chain.
    public fun is_trusted_address(
        self: &InterchainAddressTracker, chain_name: String, addr: String
    ): bool{
        get_trusted_address(self, chain_name) == &addr
    }
    // === Protected ===

    /// Create a new interchain address tracker.
    public(package) fun new(ctx: &mut TxContext): InterchainAddressTracker {
        InterchainAddressTracker {
            trusted_addresses: table::new(ctx),
        }
    }

    /// Set the trusted address for a chain or adds it if it doesn't exist.
    public(package) fun set_trusted_address(
        self: &mut InterchainAddressTracker,
        chain_name: String,
        trusted_address: String
    ) {
        if (self.trusted_addresses.contains(chain_name)) {
            if (trusted_address.length() == 0) {
                self.trusted_addresses.remove(chain_name);
            } else {
                *self.trusted_addresses.borrow_mut(chain_name) = trusted_address;
            }
        } else {
            if (trusted_address.length() > 0) {
                self.trusted_addresses.add(chain_name, trusted_address);
            }
        }
    }

    #[test]
    fun test_address_tracker() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let chain1 = std::ascii::string(b"chain1");
        let chain2 = std::ascii::string(b"chain2");
        let address1 = std::ascii::string(b"address1");
        let address2 = std::ascii::string(b"address2");

        self.set_trusted_address(chain1, address1);
        self.set_trusted_address(chain2, address2);

        assert!(self.get_trusted_address(chain1) == &address1, 0);
        assert!(self.get_trusted_address(chain2) == &address2, 1);

        assert!(self.is_trusted_address(chain1, address1) == true, 2);
        assert!(self.is_trusted_address(chain1, address2) == false, 3);
        assert!(self.is_trusted_address(chain2, address1) == false, 4);
        assert!(self.is_trusted_address(chain2, address2) == true, 5);


        self.set_trusted_address(chain1, address2);
        self.set_trusted_address(chain2, address1);

        assert!(self.get_trusted_address(chain1) == &address2, 6);
        assert!(self.get_trusted_address(chain2) == &address1, 7);

        assert!(self.is_trusted_address(chain1, address1) == false, 8);
        assert!(self.is_trusted_address(chain1, address2) == true, 9);
        assert!(self.is_trusted_address(chain2, address1) == true, 10);
        assert!(self.is_trusted_address(chain2, address2) == false, 11);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = ENoAddress)]
    fun test_address_tracker_get_no_address() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let chain1 = std::ascii::string(b"chain1");
        let address1 = std::ascii::string(b"address1");

        self.set_trusted_address(chain1, address1);
        self.set_trusted_address(chain1, std::ascii::string(b""));

        self.get_trusted_address(chain1);

        sui::test_utils::destroy(self);
    }


    #[test]
    #[expected_failure(abort_code = ENoAddress)]
    fun test_address_tracker_check_no_address() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let chain1 = std::ascii::string(b"chain1");
        let address1 = std::ascii::string(b"address1");

        self.set_trusted_address(chain1, address1);
        self.set_trusted_address(chain1, std::ascii::string(b""));

        self.is_trusted_address(chain1, address1);

        sui::test_utils::destroy(self);
    }
}
