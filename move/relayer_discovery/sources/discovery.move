/// This module implements a discovery mechanic for the Relayer to be able to
/// call some (!) transactions automatically.
///
/// Warning: this solution does allow for any transaction to be executed and
/// should be treated as a reference and a temporary solution until there's a
/// proper discovery / execution mechanism in place.
module relayer_discovery::discovery;

use axelar_gateway::channel::Channel;
use relayer_discovery::relayer_discovery_v0::{Self, RelayerDiscovery_v0};
use relayer_discovery::transaction::Transaction;
use std::ascii;
use sui::versioned::{Self, Versioned};
use version_control::version_control::{Self, VersionControl};

/// -------
/// Version
/// -------
/// This is the version of the package that should change every package upgrade.
const VERSION: u64 = 0;
/// This is the version of the data that should change when we need to migrate `Versioned` type (e.g. from `RelayerDiscovery_v0` to `RelayerDiscoveryV1`)
const DATA_VERSION: u64 = 0;

/// -------
/// Structs
/// -------
public struct RelayerDiscovery has key {
    id: UID,
    inner: Versioned,
}

fun init(ctx: &mut TxContext) {
    let inner = versioned::create(
        DATA_VERSION,
        relayer_discovery_v0::new(
            version_control(),
            ctx,
        ),
        ctx,
    );
    transfer::share_object(RelayerDiscovery {
        id: object::new(ctx),
        inner,
    });
}

/// ------
/// Macros
/// ------
macro fun value(
    $self: &RelayerDiscovery,
    $function_name: vector<u8>,
): &RelayerDiscovery_v0 {
    let relayer_discovery = $self;
    let value = relayer_discovery.inner.load_value<RelayerDiscovery_v0>();
    value.version_control().check(VERSION, ascii::string($function_name));
    value
}

macro fun value_mut(
    $self: &mut RelayerDiscovery,
    $function_name: vector<u8>,
): &mut RelayerDiscovery_v0 {
    let relayer_discovery = $self;
    let value = relayer_discovery.inner.load_value_mut<RelayerDiscovery_v0>();
    value.version_control().check(VERSION, ascii::string($function_name));
    value
}

/// During the creation of the object, the UID should be passed here to
/// receive the Channel and emit an event which will be handled by the
/// Relayer.
///
/// Example:
/// ```
/// let id = object::new(ctx);
/// let channel = discovery::create_configuration(
///    relayer_discovery, &id, contents, ctx
/// );
/// let wrapper = ExampleWrapper { id, channel };
/// transfer::share_object(wrapper);
/// ```
///
/// Note: Wrapper must be a shared object so that Relayer can access it.
public fun register_transaction(
    self: &mut RelayerDiscovery,
    channel: &Channel,
    tx: Transaction,
) {
    let value = self.value_mut!(b"register_transaction");
    let channel_id = channel.id();
    value.set_transaction(channel_id, tx);
}

public fun remove_transaction(self: &mut RelayerDiscovery, channel: &Channel) {
    let value = self.value_mut!(b"remove_transaction");
    let channel_id = channel.id();
    value.remove_transaction(channel_id);
}

/// Get a transaction for a specific channel by the channel `ID`.
public fun get_transaction(
    self: &RelayerDiscovery,
    channel_id: ID,
): Transaction {
    let value = self.value!(b"register_transaction");
    value.get_transaction(channel_id)
}

/// -----------------
/// Private Functions
/// -----------------
fun version_control(): VersionControl {
    version_control::new(vector[
        // version 0
        vector[
            b"register_transaction",
            b"remove_transaction",
            b"get_transaction",
        ].map!(|function_name| function_name.to_ascii_string()),
    ])
}

#[test_only]
use relayer_discovery::transaction;

#[test_only]
public fun new(ctx: &mut TxContext): RelayerDiscovery {
    RelayerDiscovery {
        id: object::new(ctx),
        inner: versioned::create(
            VERSION,
            relayer_discovery_v0::new(version_control(), ctx),
            ctx,
        ),
    }
}

#[test]
fun test_register_and_get() {
    let ctx = &mut sui::tx_context::dummy();
    let mut self = new(ctx);
    let channel = axelar_gateway::channel::new(ctx);

    let move_call = transaction::new_move_call(
        transaction::new_function(
            @0x1234,
            std::ascii::string(b"module"),
            std::ascii::string(b"function"),
        ),
        vector::empty<vector<u8>>(),
        vector::empty<std::ascii::String>(),
    );
    let input_transaction = transaction::new_transaction(
        true,
        vector[move_call],
    );

    self.register_transaction(&channel, input_transaction);

    let transaction = self.get_transaction(channel.id());
    assert!(transaction == input_transaction);

    sui::test_utils::destroy(self);
    sui::test_utils::destroy(channel);
}
