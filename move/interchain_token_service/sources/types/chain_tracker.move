/// Q: why addresses are stored as Strings?
/// Q: why chains are Strings?
module interchain_token_service::chain_tracker;

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

public struct TrustedChain has store, drop {}

/// The interchain address tracker stores the trusted addresses for each chain.
public struct InterchainChainTracker has store {
    trusted_chains: Bag,
}

// -----------------
// Package Functions
// -----------------
/// Check if the given address is trusted for the given chain.
public(package) fun is_trusted_chain(self: &InterchainChainTracker, chain_name: String): bool {
    self.trusted_chains.contains(chain_name)
}

/// Create a new interchain address tracker.
public(package) fun new(ctx: &mut TxContext): InterchainChainTracker {
    InterchainChainTracker {
        trusted_chains: bag::new(ctx),
    }
}

/// Set the trusted address for a chain or adds it if it doesn't exist.
public(package) fun add_trusted_chain(self: &mut InterchainChainTracker, chain_name: String) {
    assert!(chain_name.length() > 0, EEmptyChainName);

    if (self.trusted_chains.contains(chain_name)) {
        abort EAlreadyTrusted
    } else {
        self.trusted_chains.add(chain_name, TrustedChain {});
    };
    events::trusted_chain_added(chain_name);
}

public(package) fun remove_trusted_chain(self: &mut InterchainChainTracker, chain_name: String) {
    assert!(chain_name.length() > 0, EEmptyChainName);
    self.trusted_chains.remove<String, TrustedChain>(chain_name);
    events::trusted_chain_removed(chain_name);
}

// -----
// Tests
// -----
#[test]
fun test_chain_tracker() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let chain1 = std::ascii::string(b"chain1");
    let chain2 = std::ascii::string(b"chain2");

    self.add_trusted_chain(chain1);
    self.add_trusted_chain(chain2);

    assert!(self.is_trusted_chain(chain1) == true);
    assert!(self.is_trusted_chain(chain2) == true);

    assert!(self.trusted_chains.contains(chain1));
    assert!(self.trusted_chains.contains(chain2));

    self.remove_trusted_chain(chain1);
    self.remove_trusted_chain(chain2);

    assert!(self.is_trusted_chain(chain1) == false);
    assert!(self.is_trusted_chain(chain2) == false);

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

    self.add_trusted_chain(chain);

    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EAlreadyTrusted)]
fun test_add_trusted_chain_already_trusted() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let chain = std::ascii::string(b"chain");

    self.add_trusted_chain(chain);
    self.add_trusted_chain(chain);

    sui::test_utils::destroy(self);
}

#[test]
fun test_remove_trusted_chain() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let chain = std::ascii::string(b"chain");

    self.add_trusted_chain(chain);
    self.remove_trusted_chain(chain);

    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = EEmptyChainName)]
fun test_remove_trusted_chain_empty_chain_name() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let chain = std::ascii::string(b"");

    self.remove_trusted_chain(chain);

    sui::test_utils::destroy(self);
}
