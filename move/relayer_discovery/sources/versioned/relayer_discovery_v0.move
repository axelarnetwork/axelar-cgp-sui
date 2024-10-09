module relayer_discovery::relayer_discovery_v0;

use relayer_discovery::transaction::Transaction;
use sui::table::{Self, Table};
use version_control::version_control::VersionControl;

// -------
// Structs
// -------
/// A central shared object that stores discovery configuration for the
/// Relayer. The Relayer will use this object to discover and execute the
/// transactions when a message is targeted at specific channel.
public struct RelayerDiscovery_v0 has store {
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
public(package) fun new(
    version_control: VersionControl,
    ctx: &mut TxContext,
): RelayerDiscovery_v0 {
    RelayerDiscovery_v0 {
        configurations: table::new<ID, Transaction>(ctx),
        version_control,
    }
}

public(package) fun set_transaction(
    self: &mut RelayerDiscovery_v0,
    id: ID,
    transaction: Transaction,
) {
    if (self.configurations.contains(id)) {
        self.configurations.remove(id);
    };
    self.configurations.add(id, transaction);
}

public(package) fun remove_transaction(
    self: &mut RelayerDiscovery_v0,
    id: ID,
): Transaction {
    assert!(self.configurations.contains(id), EChannelNotFound);
    self.configurations.remove(id)
}

public(package) fun get_transaction(
    self: &RelayerDiscovery_v0,
    id: ID,
): Transaction {
    assert!(self.configurations.contains(id), EChannelNotFound);
    self.configurations[id]
}

public(package) fun version_control(
    self: &RelayerDiscovery_v0,
): &VersionControl {
    &self.version_control
}

// ---------
// Test Only
// ---------
#[test_only]
public(package) fun destroy_for_testing(self: RelayerDiscovery_v0) {
    sui::test_utils::destroy(self);
}

#[test_only]
fun dummy(ctx: &mut TxContext): RelayerDiscovery_v0 {
    RelayerDiscovery_v0 {
        configurations: table::new<ID, Transaction>(ctx),
        version_control: version_control::version_control::new(vector[]),
    }
}

// ----
// Test
// ----
#[test]
fun test_set_transaction_channel_not_found() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = dummy(ctx);
    let id = object::id_from_address(@0x1);
    let transaction = relayer_discovery::transaction::new_transaction(
        true,
        vector[],
    );
    self.set_transaction(id, transaction);
    self.set_transaction(id, transaction);
    self.destroy_for_testing();
}

#[test]
#[expected_failure(abort_code = EChannelNotFound)]
fun test_get_transaction_channel_not_found() {
    let ctx = &mut sui::tx_context::dummy();
    let self = dummy(ctx);
    self.get_transaction(object::id_from_address(@0x1));
    self.destroy_for_testing();
}

#[test]
#[expected_failure(abort_code = EChannelNotFound)]
fun test_remove_transaction_channel_not_found() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = dummy(ctx);
    self.remove_transaction(object::id_from_address(@0x1));
    self.destroy_for_testing();
}
