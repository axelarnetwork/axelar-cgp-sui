//
//

/// This module implements a discovery mechanic for the Relayer to be able to
/// call some (!) transactions automatically.
///
/// Warning: this solution does allow for any transaction to be executed and
/// should be treated as a reference and a temporary solution until there's a
/// proper discovery / execution mechanism in place.
module axelar::discovery {
    use std::ascii::{String};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use sui::object::{Self, ID, UID};
    use axelar::channel::{source_id, Channel};

    /// A central shared object that stores discovery configuration for the
    /// Relayer. The Relayer will use this object to discover and execute the
    /// transactions when a message is targeted at specific channel.
    struct RelayerDiscovery has key {
        id: UID,
        /// A map of channel IDs to the target that needs to be executed by the
        /// relayer. There can be only one configuration per channel.
        configurations: Table<ID, Transaction>,
    }

    struct Description has store, copy, drop {
        package_id: address,
        module_name: String,
        name: String,
    }

    /// Arguments are prefixed with:
    /// - 0 for objects followed by exactly 32 bytes that cointain the object id
    /// - 1 for pures followed by the bcs encoded form of the pure
    /// - 2 for the call contract objects, followed by nothing (to be passed into the target function)
    /// - 3 for the payload of the contract call (to be passed into the intermediate function)
    struct Transaction has store, copy, drop {
        function: Description,
        arguments: vector<vector<u8>>,
        type_arguments: vector<Description>,
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
    public fun register_transaction<T>(
        self: &mut RelayerDiscovery,
        channel: &Channel<T>,
        tx: Transaction,
    ) {
        let channel_id = source_id(channel);
        if(table::contains(&self.configurations, channel_id)) {
            table::remove(&mut self.configurations, channel_id);
        };
        table::add(&mut self.configurations, channel_id, tx);
    }

    public fun get_transaction(
        self: &mut RelayerDiscovery,
        channel_id: ID,
    ): Transaction {
        assert!(table::contains(&self.configurations, channel_id), 0);
        *table::borrow(&self.configurations, channel_id)
    }

    public fun new_description(package_id: address, module_name: String, function_or_type: String) : Description {
        Description {
            package_id,
            module_name,
            name: function_or_type,
        }
    }

    public fun new_transaction(function: Description, arguments: vector<vector<u8>>, type_arguments: vector<Description>) : Transaction {
        Transaction {
            function,
            arguments,
            type_arguments
        }
    }

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
