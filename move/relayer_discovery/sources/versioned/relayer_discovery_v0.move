module relayer_discovery::relayer_discovery_v0;

use sui::table::{Self, Table};

use version_control::version_control::VersionControl;

use relayer_discovery::transaction::Transaction;

// -------
// Structs
// -------
/// A central shared object that stores discovery configuration for the
/// Relayer. The Relayer will use this object to discover and execute the
/// transactions when a message is targeted at specific channel.
public struct RelayerDiscoveryV0 has store {
    /// A map of channel IDs to the target that needs to be executed by the
    /// relayer. There can be only one configuration per channel.
    configurations: Table<ID, Transaction>,
    /// An object to manage version control.
    version_control: VersionControl,
}

// ------
// Errors
// ------
#[error]
const EChannelNotFound: vector<u8> = b"channel not found";

// -----------------
// Package Functions
// -----------------
public(package) fun new(version_control: VersionControl, ctx: &mut TxContext): RelayerDiscoveryV0 {
    RelayerDiscoveryV0 {
        configurations: table::new<ID, Transaction>(ctx),
        version_control,
    }
}

public(package) fun set_transaction(self: &mut RelayerDiscoveryV0, id: ID, transaction: Transaction) {
    if (self.configurations.contains(id)) {
        self.configurations.remove(id);
    };
    self.configurations.add(id, transaction);
}

public(package) fun remove_transaction(self: &mut RelayerDiscoveryV0, id: ID): Transaction {
    assert!(self.configurations().contains(id), EChannelNotFound);
    self.configurations.remove(id)
}

public(package) fun get_transaction(self: &RelayerDiscoveryV0, id: ID): Transaction {
    assert!(self.configurations().contains(id), EChannelNotFound);
    self.configurations[id]
}

public(package) fun configurations(self: &RelayerDiscoveryV0): &Table<ID, Transaction> {
    &self.configurations
}

public(package) fun configurations_mut(self: &mut RelayerDiscoveryV0): &mut Table<ID, Transaction> {
    &mut self.configurations
}

public(package) fun version_control(self: &RelayerDiscoveryV0): &VersionControl {
    &self.version_control
}

// ---------
// Test Only
// ---------
#[test_only]
public(package) fun destroy_for_testing(self: RelayerDiscoveryV0) {
    sui::test_utils::destroy(self);
}
