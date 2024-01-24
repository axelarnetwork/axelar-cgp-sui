module interchain_token_service::interchain_address_tracker {
    use std::ascii::String;

    use sui::table::{Self, Table};
    use sui::tx_context::{TxContext};

    friend interchain_token_service::storage;

    /// Attempt to borrow a trusted address but it's not registered.
    const EUntrustedChain: u64 = 0;

    struct InterchainAddressTracker has store {
        trusted_addresses: Table<String, String>
    }

    public(friend) fun new(ctx: &mut TxContext): InterchainAddressTracker {
        InterchainAddressTracker {
            trusted_addresses: table::new(ctx),
        }
    }

    public(friend) fun set_trusted_address(
        self: &mut InterchainAddressTracker,
        chain_name: String,
        trusted_address: String
    ) {
        if (table::contains(&self.trusted_addresses, chain_name)) {
            *table::borrow_mut(&mut self.trusted_addresses, chain_name) = trusted_address;
        } else {
            table::add(&mut self.trusted_addresses, chain_name, trusted_address);
        }
    }

    public fun borrow_trusted_address(
        self: &InterchainAddressTracker, chain_name: String
    ): &String {
        assert!(table::contains(&self.trusted_addresses, chain_name), EUntrustedChain);
        table::borrow(&self.trusted_addresses, chain_name)
    }

    public fun is_trusted_address(
        self: &InterchainAddressTracker, chain_name: String, address: String
    ): bool{
        borrow_trusted_address(self, chain_name) == &address
    }
}
