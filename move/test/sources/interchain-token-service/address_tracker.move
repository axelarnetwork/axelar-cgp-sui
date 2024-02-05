module its::address_tracker {
    use std::ascii::String;

    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;

    friend its::its;

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
    public(friend) fun new(ctx: &mut TxContext): InterchainAddressTracker {
        InterchainAddressTracker {
            trusted_addresses: table::new(ctx),
        }
    }

    /// Set the trusted address for a chain or adds it if it doesn't exist.
    public(friend) fun set_trusted_address(
        self: &mut InterchainAddressTracker,
        chain_name: String,
        trusted_address: String
    ) {
        if (self.trusted_addresses.contains(chain_name)) {
            *self.trusted_addresses.borrow_mut(chain_name) = trusted_address;
        } else {
            self.trusted_addresses.add(chain_name, trusted_address);
        }
    }
}
