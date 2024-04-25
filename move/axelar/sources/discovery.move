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

    use sui::table::{Self, Table};
    use sui::bcs::{Self, BCS};

    use axelar::channel::Channel;

    /// TypeArgument is not a valid string.
    const EInvalidString: u64 = 0;

    /// Channel not found.
    const EChannelNotFound: u64 = 1;

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
    /// - 2 for the call contract object, followed by nothing (to be passed into the target function)
    /// - 3 for the payload of the contract call (to be passed into the intermediate function)
    /// - 4 for an argument returned from a previous move call, followed by a u8 specified which call to get the return of (0 for the first transaction AFTER the one that gets ApprovedCall out), and then another u8 specifying which argument to input. 
    public struct MoveCall has store, copy, drop {
        function: Function,
        arguments: vector<vector<u8>>,
        type_arguments: vector<String>,
    }

    public struct Transaction has store, copy, drop {
        is_final: bool,
        move_calls: vector<MoveCall>,
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
        let channel_id = channel.id();
        if (self.configurations.contains(channel_id)) {
            self.configurations.remove(channel_id);
        };
        self.configurations.add(channel_id, tx);
    }

    /// Get a transaction for a specific channel by the channel `ID`.
    public fun get_transaction(
        self: &mut RelayerDiscovery,
        channel_id: ID,
    ): Transaction {
        assert!(self.configurations.contains(channel_id), EChannelNotFound);
        *self.configurations.borrow(channel_id)
    }

    // === Tx Building ===

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

    public fun new_move_call(
        function: Function,
        arguments: vector<vector<u8>>,
        type_arguments: vector<String>
    ): MoveCall {
        MoveCall {
            function,
            arguments,
            type_arguments,
        }
    }

    public fun new_move_call_from_bcs(bcs: &mut BCS): MoveCall {
        let function = new_function_from_bcs(bcs);
        let arguments = bcs.peel_vec_vec_u8();
        let length = bcs.peel_vec_length();
        let mut type_arguments = vector[];
        let mut i = 0;

        while (i < length) {
            let mut type_argument = ascii::try_string(bcs.peel_vec_u8());
            assert!(type_argument.is_some(), EInvalidString);
            vector::push_back(&mut type_arguments, type_argument.extract());
            i = i + 1;
        };

        MoveCall {
            function,
            arguments,
            type_arguments,
        }
    }

    public fun new_transaction(is_final: bool, move_calls: vector<MoveCall>): Transaction {
        Transaction {
            is_final,
            move_calls,
        }
    }

    public fun new_transaction_from_bcs(bcs: &mut BCS): Transaction {
        let is_final = bcs.peel_bool();
        let length = bcs.peel_vec_length();
        let mut move_calls = vector[];
        let mut i = 0;

        while (i < length) {
            vector::push_back(
                &mut move_calls, 
                new_move_call_from_bcs(bcs),
            );
            i = i + 1;
        };

        Transaction {
            is_final,
            move_calls,
        }
    }

    #[test_only]
    public fun package_id(self: &Function): address {
        self.package_id
    }

    #[test_only]
    public fun module_name(self: &Function): ascii::String {
        self.module_name
    }

    #[test_only]
    public fun name(self: &Function): ascii::String {
        self.name
    }

    #[test_only]
    public fun function(self: &Transaction): Function {
        self.function
    }
 
    #[test_only]
    public fun arguments(self: &Transaction): vector<vector<u8>> {
        self.arguments
    }

    #[test_only]
    public fun type_arguments(self: &Transaction): vector<ascii::String> {
        self.type_arguments
    }

    #[test_only]
    public fun new(ctx: &mut TxContext): RelayerDiscovery {
        RelayerDiscovery {
            id: object::new(ctx),
            configurations: table::new(ctx),
        }
    }

    #[test]
    fun tx_builder() {
        let function = new_function(
            @0x1,
            ascii::string(b"ascii"),
            ascii::string(b"string"),
        );

        let _tx = function.new_transaction(
            vector[ bcs::to_bytes(&b"some_string") ], // arguments
            vector[ ], // type_arguments
        );
    }

    #[test]
    fun test_new_function_from_bcs() {
        let package_id = @0x5f7809eb09754577387a816582ece609511d0262b2c52aa15306083ca3c85962;
        let module_name = std::ascii::string(b"module");
        let name = std::ascii::string(b"function");
        let input = x"5f7809eb09754577387a816582ece609511d0262b2c52aa15306083ca3c85962066d6f64756c650866756e6374696f6e";
    
        let function = new_function_from_bcs(&mut bcs::new(input));
        assert!(function.package_id == package_id, 0);
        assert!(function.module_name == module_name, 1);
        assert!(function.name == name, 2);
    }

    #[test]
    fun test_new_transaction_from_bcs() {
        let package_id = @0x5f7809eb09754577387a816582ece609511d0262b2c52aa15306083ca3c85962;
        let module_name = std::ascii::string(b"module");
        let name = std::ascii::string(b"function");
        let arguments = vector[x"1234", x"5678"];
        let type_arguments = vector[ascii::string(b"type1"), ascii::string(b"type2")];
        let input = x"5f7809eb09754577387a816582ece609511d0262b2c52aa15306083ca3c85962066d6f64756c650866756e6374696f6e0202123402567802057479706531057479706532";
    
        let transaction = new_transaction_from_bcs(&mut bcs::new(input));
        assert!(transaction.function.package_id == package_id, 0);
        assert!(transaction.function.module_name == module_name, 1);
        assert!(transaction.function.name == name, 2);
        assert!(transaction.arguments == arguments, 3);
        assert!(transaction.type_arguments == type_arguments, 4);
    }

    #[test]
    fun test_register_and_get() {
        let ctx = &mut sui::tx_context::dummy();
        let mut self = new(ctx);
        let channel = axelar::channel::new(ctx);

        let input_transaction = Transaction {
            function: Function {
                package_id: @0x1234,
                module_name: std::ascii::string(b"module"),
                name: std::ascii::string(b"function"),
            },
            arguments: vector::empty<vector<u8>>(),
            type_arguments: vector::empty<ascii::String>(),
        };
        
        self.register_transaction(&channel, input_transaction);

        let transaction = self.get_transaction(channel.id());
        assert!(transaction == input_transaction, 0);
        
        sui::test_utils::destroy(self);
        sui::test_utils::destroy(channel);
    }
}
