module its::interchain_address_tracker {
    use std::ascii::{Self, String};

    use sui::table::{Self, Table};
    use sui::tx_context::{TxContext};

    friend its::storage;

    /// Attempt to borrow a trusted address but it's not registered.
    const ENoAddress: u64 = 0;

    /// The interchain address tracker stores the trusted addresses for each chain.
    struct InterchainAddressTracker has store {
        trusted_addresses: Table<String, String>,
        axelar_chain_name: String,
        axelar_governance_address: String,
    }

    /// Get the trusted address for a chain.
    public fun get_trusted_address(
        self: &InterchainAddressTracker, chain_name: String
    ): &String {
        assert!(table::contains(&self.trusted_addresses, chain_name), ENoAddress);
        table::borrow(&self.trusted_addresses, chain_name)
    }

    /// Check if the given address is trusted for the given chain.
    public fun is_trusted_address(
        self: &InterchainAddressTracker, chain_name: String, addr: String
    ): bool{
        get_trusted_address(self, chain_name) == &addr
    }

    public fun is_axelar_governance(
        self: &InterchainAddressTracker, 
        chain_name: String, 
        addr: String
    ): bool{
        &chain_name == &self.axelar_chain_name && &addr == &self.axelar_governance_address
    }

    // === Protected ===

    /// Create a new interchain address tracker.
    public(friend) fun new(ctx: &mut TxContext, axelar_chain_name: String, axelar_governance_address: String): InterchainAddressTracker {
        InterchainAddressTracker {
            trusted_addresses: table::new(ctx),
            axelar_chain_name,
            axelar_governance_address,
        }
    }

    /// Set the trusted address for a chain or adds it if it doesn't exist.
    public(friend) fun set_trusted_address(
        self: &mut InterchainAddressTracker,
        chain_name: String,
        trusted_address: String
    ) {
        if (table::contains(&self.trusted_addresses, chain_name)) {
            if (ascii::length(&trusted_address) == 0) {
                table::remove(&mut self.trusted_addresses, chain_name);
            } else {
                *table::borrow_mut(&mut self.trusted_addresses, chain_name) = trusted_address;
            }
        } else {
            if (ascii::length(&trusted_address) > 0) {
                table::add(&mut self.trusted_addresses, chain_name, trusted_address);
            }
        }
    }
}
