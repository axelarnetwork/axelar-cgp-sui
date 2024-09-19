/// This module implements a discovery mechanic for the Relayer to be able to
/// call some (!) transactions automatically.
///
/// Warning: this solution does allow for any transaction to be executed and
/// should be treated as a reference and a temporary solution until there's a
/// proper discovery / execution mechanism in place.
module axelar_gateway::discovery;

use sui::versioned::{Self, Versioned};

use version_control::version_control::{Self, VersionControl};

use axelar_gateway::channel::Channel;
use axelar_gateway::transaction::Transaction;
use axelar_gateway::relayer_discovery_v0::{Self, RelayerDiscoveryV0};

/// Channel not found.
const EChannelNotFound: u64 = 0;

/// -------
/// Version
/// -------
/// This is the version of the package that should change every package upgrade.
const VERSION: u64 = 0;
/// This is the version of the data that should change when we need to migrate `Versioned` type (e.g. from `RelayerDiscoveryV0` to `RelayerDiscoveryV1`)
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
/// macros
/// ------
macro fun value($self: &RelayerDiscovery): &RelayerDiscoveryV0 {
    let relayer_discovery = $self;
    relayer_discovery.inner.load_value<RelayerDiscoveryV0>()
}

macro fun value_mut($self: &mut RelayerDiscovery): &mut RelayerDiscoveryV0 {
    let relayer_discovery = $self;
    relayer_discovery.inner.load_value_mut<RelayerDiscoveryV0>()
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
    let value = self.value_mut!();
    value.version_control().check(VERSION, b"register_transaction");
    let channel_id = channel.id();
    if (value.configurations().contains(channel_id)) {
        value.configurations_mut().remove(channel_id);
    };
    value.configurations_mut().add(channel_id, tx);
}

/// Get a transaction for a specific channel by the channel `ID`.
public fun get_transaction(
    self: &mut RelayerDiscovery,
    channel_id: ID,
): Transaction {
    let value = self.value!();
    value.version_control().check(VERSION, b"register_transaction");
    assert!(value.configurations().contains(channel_id), EChannelNotFound);
    value.configurations()[channel_id]
}

/// -----------------
/// Private Functions
/// -----------------
fun version_control(): VersionControl {
    version_control::new(
        vector[
            // version 0
            vector[b"register_transaction"],
            vector[b"get_transaction"],
        ]
    )
}

#[test_only]
use axelar_gateway::transaction;

#[test_only]
public fun new(ctx: &mut TxContext): RelayerDiscovery {
    RelayerDiscovery {
        id: object::new(ctx),
        inner: versioned::create(
            VERSION,
            relayer_discovery_v0::new(version_control(), ctx),
            ctx,
        )
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
    assert!(transaction == input_transaction, 0);

    sui::test_utils::destroy(self);
    sui::test_utils::destroy(channel);
}
