

module its::discovery {
    use std::ascii;
    use std::type_name;

    use sui::address;
    use sui::hex;
    use sui::bcs;

    use abi::abi::{Self, AbiReader};

    use axelar::discovery::{Self, RelayerDiscovery, Transaction};

    use its::its::ITS;
    use its::token_id;

    const EUnsupportedMessageType: u64 = 0;

    const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
    const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
    //const MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;

    public fun register_transaction(self: &ITS, discovery: &mut RelayerDiscovery) {
        let mut arg = vector[0];
        vector::append(&mut arg, bcs::to_bytes(&object::id(self)));

        let arguments = vector[
            arg,
            vector[3]
        ];

        let function = discovery::new_function(
            its_package_id(),
            ascii::string(b"discovery"),
            ascii::string(b"get_call_info")
        );

        let tx = discovery::new_transaction(
            function,
            arguments,
            vector[],
        );

        discovery.register_transaction(self.channel(), tx);
    }

    public fun get_call_info(self: &ITS, payload: vector<u8>): vector<Transaction> {
        let reader = abi::new_reader(payload);
        let message_type = reader.read_u256(0);
        if (message_type == MESSAGE_TYPE_INTERCHAIN_TRANSFER) {
            get_interchain_transfer_tx(self, &reader)
        } else {
            assert!(message_type == MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, EUnsupportedMessageType);
            vector[get_deploy_interchain_token_tx(self, &reader)]
        }
    }

    fun get_interchain_transfer_tx(self: &ITS, reader: &AbiReader): vector<Transaction> {
        let data = reader.read_bytes(5);

        if (vector::is_empty(&data)) {
            let mut arg = vector[0];
            vector::append(&mut arg, address::to_bytes(object::id_address(self)));

            let arguments = vector[
                arg,
                vector[2]
            ];

            let token_id = token_id::from_u256(reader.read_u256(1));
            let type_name = self.get_registered_coin_type(token_id);

            vector[discovery::new_transaction(
                discovery::new_function(
                    its_package_id(),
                    ascii::string(b"service"),
                    ascii::string(b"receive_interchain_transfer")
                ),
                arguments,
                vector[ type_name::into_string(*type_name) ],
            )]
        } else {
            let transaction = abi::new_reader(data).read_bytes(0);
            let mut bcs = bcs::new(transaction);
            let length = bcs.peel_vec_length();
            let mut block = vector[];
            let mut i = 0;
            while ( i < length ) {
                vector::push_back(&mut block, discovery::new_transaction_from_bcs(&mut bcs));
                i = i + 1;
            };
            block
        }
    }

    fun get_deploy_interchain_token_tx(self: &ITS, reader: &AbiReader): Transaction {
        let mut arg = vector[0];
        vector::append(&mut arg, address::to_bytes(object::id_address(self)));

        let arguments = vector[
            arg,
            vector[2]
        ];

        let symbol = ascii::string(reader.read_bytes(3));
        let decimals = (reader.read_u256(4) as u8);
        let type_name = self.get_unregistered_coin_type(&symbol, decimals);

        discovery::new_transaction(
            discovery::new_function(
                its_package_id(),
                ascii::string(b"service"),
                ascii::string(b"receive_deploy_interchain_token")
            ),
            arguments,
            vector[ type_name::into_string(*type_name) ],
        )
    }

    /// Returns the address of the ITS module (from the type name).
    fun its_package_id(): address {
        address::from_bytes(
            hex::decode(
                *ascii::as_bytes(
                    &type_name::get_address(&type_name::get<ITS>())
                )
            )
        )
    }

    #[test_only]
    fun get_initial_tx(self: &ITS): Transaction {
        let mut arg = vector[0];
        vector::append(&mut arg, bcs::to_bytes(&object::id(self)));

        let arguments = vector[
            arg,
            vector[3]
        ];

        let function = discovery::new_function(
            its_package_id(),
            ascii::string(b"discovery"),
            ascii::string(b"get_call_info")
        );

        discovery::new_transaction(
            function,
            arguments,
            vector[],
        )
    }

    #[test]
    fun test_discovery_initial() {
        let ctx = &mut sui::tx_context::dummy();
        let its = its::its::new();
        let mut discovery = axelar::discovery::new(ctx);

        register_transaction(&its, &mut discovery);

        assert!(discovery.get_transaction(its.channel_id()) == get_initial_tx(&its), 0);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(discovery);
    }

    #[test]
    fun test_discovery_interchain_transfer() {
        let ctx = &mut sui::tx_context::dummy();
        let mut its = its::its::new();
        let mut discovery = axelar::discovery::new(ctx);

        register_transaction(&its, &mut discovery);

        let token_id = @0x1234;
        let source_address = b"source address";
        let target_channel = @0x5678;
        let amount = 1905;
        let data = b"";
        let mut writer = abi::new_writer(6);
        writer            
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(address::to_u256(token_id))
            .write_bytes(source_address)
            .write_bytes(address::to_bytes(target_channel))
            .write_u256(amount)
            .write_bytes(data);
        let payload = writer.into_bytes();

        let type_arg = std::type_name::get<RelayerDiscovery>();
        its.test_add_registered_coin_type(its::token_id::from_address(token_id), type_arg);
        let mut tx_block = get_call_info(&its, payload);
        assert!(tx_block == vector[get_interchain_transfer_tx(&its, &abi::new_reader(payload))], 1);
        let call_info = vector::pop_back(&mut tx_block);

        assert!(call_info.function().package_id() == its_package_id(), 2);
        assert!(call_info.function().module_name() == ascii::string(b"service"), 3);
        assert!(call_info.function().name() == ascii::string(b"receive_interchain_transfer"), 4);
        let mut arg = vector[0];
        vector::append(&mut arg, address::to_bytes(object::id_address(&its)));

        let arguments = vector[
            arg,
            vector[2]
        ];
        assert!(call_info.arguments() == arguments, 5);
        assert!(call_info.type_arguments() == vector[type_arg.into_string()], 6);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(discovery);
    }

    #[test]
    fun test_discovery_interchain_transfer_with_data() {
        let ctx = &mut sui::tx_context::dummy();
        let mut its = its::its::new();
        let mut discovery = axelar::discovery::new(ctx);

        register_transaction(&its, &mut discovery);

        assert!(discovery.get_transaction(its.channel_id()) == get_initial_tx(&its), 0);

        let token_id = @0x1234;
        let source_address = b"source address";
        let target_channel = @0x5678;
        let amount = 1905;
        let tx_data = bcs::to_bytes(&get_initial_tx(&its));
        let mut writer = abi::new_writer(2);
        writer
            .write_bytes(tx_data)
            .write_u256(1245);
        let data = writer.into_bytes();
        
        writer = abi::new_writer(6);
        writer            
            .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
            .write_u256(address::to_u256(token_id))
            .write_bytes(source_address)
            .write_bytes(address::to_bytes(target_channel))
            .write_u256(amount)
            .write_bytes(data);
        let payload = writer.into_bytes();

        its.test_add_registered_coin_type(its::token_id::from_address(token_id), std::type_name::get<RelayerDiscovery>());
        assert!(get_call_info(&its, payload) == vector[get_interchain_transfer_tx(&its, &abi::new_reader(payload))], 1);
        
        sui::test_utils::destroy(its);
        sui::test_utils::destroy(discovery);
    }

    #[test]
    fun test_discovery_deploy_token() {
        let ctx = &mut sui::tx_context::dummy();
        let mut its = its::its::new();
        let mut discovery = axelar::discovery::new(ctx);

        register_transaction(&its, &mut discovery);

        let token_id = @0x1234;
        let name = b"name";
        let symbol = b"symbol";
        let decimals = 15;
        let distributor = x"0325";
        let mut writer = abi::new_writer(6);
        writer            
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(address::to_u256(token_id))
            .write_bytes(name)
            .write_bytes(symbol)
            .write_u256(decimals)
            .write_bytes(distributor);
        let payload = writer.into_bytes();

        let type_arg = std::type_name::get<RelayerDiscovery>();
        its.test_add_unregistered_coin_type(its::token_id::unregistered_token_id(&ascii::string(symbol), (decimals as u8)), type_arg);
        let mut tx_block = get_call_info(&its, payload);
        assert!(tx_block == vector[get_deploy_interchain_token_tx(&its, &abi::new_reader(payload))], 1);

        let call_info = vector::pop_back(&mut tx_block);
        assert!(call_info.function().package_id() == its_package_id(), 2);
        assert!(call_info.function().module_name() == ascii::string(b"service"), 3);
        assert!(call_info.function().name() == ascii::string(b"receive_deploy_interchain_token"), 4);
        let mut arg = vector[0];
        vector::append(&mut arg, address::to_bytes(object::id_address(&its)));

        let arguments = vector[
            arg,
            vector[2]
        ];
        assert!(call_info.arguments() == arguments, 5);
        assert!(call_info.type_arguments() == vector[type_arg.into_string()], 6);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(discovery);
    }

}
