// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This module implements a discovery mechanic for the Relayer to be able to
/// call some (!) transactions automatically.
///
/// Warning: this solution does allow for any transaction to be executed and
/// should be treated as a reference and a temporary solution until there's a
/// proper discovery / execution mechanism in place.
module axelar::discovery {
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use sui::object::{Self, ID, UID};
    use axelar::channel::{Self, source_id, Channel};

    /// A central shared object that stores discovery configuration for the
    /// Relayer. The Relayer will use this object to discover and execute the
    /// transactions when a message is targeted at specific channel.
    struct RelayerDiscovery has key {
        id: UID,
        /// A map of channel IDs to the target that needs to be executed by the
        /// relayer. There can be only one configuration per channel.
        configurations: Table<ID, Target>,
    }

    /// The target configuration for the Relayer call.
    struct Target has store, drop {
        /// The transaction that should be executed by the Relayer. Transaction
        /// bytes are stored in a pre-serialized format, similar to the
        ///
        /// TransactionData definition in Sui Node codebase, however, some parts
        /// are simplified to fetch versions at the time of calling.
        transaction: Option<vector<u8>>,
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
    public fun create_configuration<T: store>(
        self: &mut RelayerDiscovery,
        channel: &Channel<T>,
        ctx: &mut TxContext
    ) {
        let channel_id = object::id_from_bytes(source_id(channel));

        table::add(&mut self.configurations, channel_id, Target {
            transaction: option::none()
        });
    }

    /// A function that should be used to register an action performed by the
    /// Relayer. The action will be executed on the object with the given UID.
    /// Additional parameters can be passed in a pre-serialized transaction
    /// format.
    ///
    /// The function can be called multiple times, every time overriding the
    /// previous action stored in the Relayer storage.
    public fun register_transaction<T: store>(
        self: &mut RelayerDiscovery,
        channel: &Channel<T>,
        transaction: vector<u8>,
    ) {
        let channel_id = object::id_from_bytes(source_id(channel));
        let record_mut: &mut Target = table::borrow_mut(
            &mut self.configurations,
            channel_id
        );

        record_mut.transaction = option::some(transaction);
    }

    // please call 0x000000::register_transaction::give_me_payload(): vector<u8>

    // === Internal ===

    #[test_only]
    struct CallTarget has copy, store, drop {
        package: address,
        module_: String,
        function: String,
    }

    #[test_only]
    /// This struct exists to illustrate the BCS format for the TransactionData
    /// used in the Relayer discovery mechanism. Use it as a reference when
    /// preparing the transaction bytes for the relayer registry.
    struct TransactionData has copy, store, drop {
        /// List of type arguments for the transaction.
        type_arguments: vector<String>,

        /// The arguments are an Enum which has two possible values:
        /// 0: address - Object ID of the Argument
        /// 1: vector<u8> - Pure Argument
        /// 2: ApprovedCall
        ///
        /// According to the BCS spec: the enum is represented as a single ULEB
        /// byte, followed by the value of the enum. Given that there's only two
        /// possible values, 0 stands for an ObjectArgument, 1 stands for the
        /// VectorArgument, 2 stands for the ApprovedCall argument.
        arguments: vector<vector<u8>>,

        /// The function to call.
        target: CallTarget,
    }

    fun init(ctx: &mut TxContext) {
        sui::transfer::share_object(RelayerDiscovery {
            id: object::new(ctx),
            configurations: table::new(ctx),
        });
    }
}