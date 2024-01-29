// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This module implements a discovery mechanic for the Relayer to be able to
/// call some (!) transactions automatically.
///
/// Warning: this solution does allow for any transaction to be executed and
/// should be treated as a reference and a temporary solution until there's a
/// proper discovery / execution mechanism in place.
module axelar::discovery {
    use std::ascii::{Self, String};
    use std::vector;

    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use sui::object::{Self, ID, UID};
    use sui::bcs::{Self, BCS};
    use sui::transfer;

    use axelar::channel::{source_id, Channel};

    /// A central shared object that stores discovery configuration for the
    /// Relayer. The Relayer will use this object to discover and execute the
    /// transactions when a message is targeted at specific channel.
    public struct RelayerDiscovery has key {
        id: UID,
        /// A map of channel IDs to the target that needs to be executed by the
        /// relayer. There can be only one configuration per channel.
        configurations: Table<ID, Transaction>,
    }

    public struct Function has store, copy, drop {
        package_id: address,
        module_name: String,
        name: String,
    }

    /// Arguments are prefixed with:
    /// - 0 for objects followed by exactly 32 bytes that cointain the object id
    /// - 1 for pures followed by the bcs encoded form of the pure
    /// - 2 for the call contract objects, followed by nothing (to be passed into the target function)
    /// - 3 for the payload of the contract call (to be passed into the intermediate function)
    public struct Transaction has store, copy, drop {
        function: Function,
        arguments: vector<vector<u8>>,
        type_arguments: vector<String>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(RelayerDiscovery {
            id: object::new(ctx),
            configurations: table::new(ctx),
        });
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
        let channel_id = source_id(channel);
        if (self.configurations.contains(channel_id)) {
            self.configurations.remove(channel_id);
        };
        self.configurations.add(channel_id, tx);
    }

    public fun get_transaction(
        self: &mut RelayerDiscovery,
        channel_id: ID,
    ): Transaction {
        assert!(table::contains(&self.configurations, channel_id), 0);
        *self.configurations.borrow(channel_id)
    }

    public fun new_function(
        package_id: address, module_name: String, name: String
    ): Function {
        Function {
            package_id,
            module_name,
            name,
        }
    }

    public fun new_function_from_bcs(bcs: &mut BCS): Function {
        Function {
            package_id: bcs::peel_address(bcs),
            module_name: ascii::string(bcs::peel_vec_u8(bcs)),
            name: ascii::string(bcs::peel_vec_u8(bcs)),
        }
    }

    public fun new_transaction(
        function: Function,
        arguments: vector<vector<u8>>,
        type_arguments: vector<String>
    ): Transaction {
        Transaction {
            function,
            arguments,
            type_arguments,
        }
    }

    public fun new_transaction_from_bcs(bcs: &mut BCS): Transaction {
        let function = new_function_from_bcs(bcs);
        let arguments = bcs.peel_vec_vec_u8();
        let length = bcs.peel_vec_length();
        let mut type_arguments = vector[];
        let mut i = 0;

        while (i < length) {
            let type_argument = ascii::string(bcs.peel_vec_u8());
            vector::push_back(&mut type_arguments, type_argument);
            i = i + 1;
        };

        Transaction {
            function,
            arguments,
            type_arguments,
        }
    }

}
