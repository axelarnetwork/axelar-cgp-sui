/// Q: why addresses are stored as Strings?
/// Q: why chains are Strings?
module its::address_tracker;

use std::ascii::String;
use sui::table::{Self, Table};

// ------
// Errors
// ------
#[error]
const ENoAddress: vector<u8> = b"attempt to borrow a trusted address but it's not registered";
#[error]
const EEmptyChainName: vector<u8> = b"empty trusted chain name is unsupported";
#[error]
const EEmptyTrustedAddress: vector<u8> = b"empty trusted address is unsupported";

/// The interchain address tracker stores the trusted addresses for each chain.
public struct InterchainAddressTracker has store {
    trusted_addresses: Table<String, String>,
}

// -------
// Getters
// -------
/// Get the trusted address for a chain.
public fun trusted_address(
    self: &InterchainAddressTracker,
    chain_name: String,
): &String {
    assert!(self.trusted_addresses.contains(chain_name), ENoAddress);
    &self.trusted_addresses[chain_name]
}

/// Check if the given address is trusted for the given chain.
public fun is_trusted_address(
    self: &InterchainAddressTracker,
    chain_name: String,
    addr: String,
): bool {
    trusted_address(self, chain_name) == &addr
}

// -----------------
// Package Functions
// -----------------
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
    trusted_address: String,
) {
    assert!(chain_name.length() > 0, EEmptyChainName);
    assert!(trusted_address.length() > 0, EEmptyTrustedAddress);

    if (self.trusted_addresses.contains(chain_name)) {
        *&mut self.trusted_addresses[chain_name] = trusted_address;
    } else {
        self.trusted_addresses.add(chain_name, trusted_address);
    }
}

public(package) fun remove_trusted_address(
    self: &mut InterchainAddressTracker,
    chain_name: String,
) {
    assert!(chain_name.length() > 0, EEmptyChainName);
    self.trusted_addresses.remove(chain_name);
}

// -----
// Tests
// -----
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

    assert!(self.trusted_address(chain1) == &address1);
    assert!(self.trusted_address(chain2) == &address2);

    assert!(self.is_trusted_address(chain1, address1) == true);
    assert!(self.is_trusted_address(chain1, address2) == false);
    assert!(self.is_trusted_address(chain2, address1) == false);
    assert!(self.is_trusted_address(chain2, address2) == true);

    self.set_trusted_address(chain1, address2);
    self.set_trusted_address(chain2, address1);

    assert!(self.trusted_address(chain1) == &address2);
    assert!(self.trusted_address(chain2) == &address1);

    assert!(self.is_trusted_address(chain1, address1) == false);
    assert!(self.is_trusted_address(chain1, address2) == true);
    assert!(self.is_trusted_address(chain2, address1) == true);
    assert!(self.is_trusted_address(chain2, address2) == false);

    assert!(self.trusted_addresses.contains(chain1));
    assert!(self.trusted_addresses.contains(chain2));

    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EEmptyChainName)]
fun test_set_trusted_address_empty_chain_name() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let chain = std::ascii::string(b"");
    let address = std::ascii::string(b"address");

    self.set_trusted_address(chain, address);

    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EEmptyTrustedAddress)]
fun test_set_trusted_address_empty_trusted_address() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let chain = std::ascii::string(b"chain");
    let address = std::ascii::string(b"");

    self.set_trusted_address(chain, address);

    sui::test_utils::destroy(self);
}


#[test]
fun test_remove_trusted_address() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let chain = std::ascii::string(b"chain");
    let address = std::ascii::string(b"address");

    self.set_trusted_address(chain, address);
    self.remove_trusted_address(chain);

    sui::test_utils::destroy(self);
}


#[test]
#[expected_failure(abort_code = EEmptyChainName)]
fun test_remove_trusted_address_empty_chain_name() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let chain = std::ascii::string(b"");

    self.remove_trusted_address(chain);

    sui::test_utils::destroy(self);
}
