

module its::discovery {
    use std::ascii;
    use std::type_name;

    use sui::address;
    use sui::bcs;

    use abi::abi::{Self, AbiReader};

    use axelar_gateway::discovery::{Self, RelayerDiscovery, Transaction, package_id};

    use its::its::ITS;
    use its::token_id::{Self, TokenId};

    const EUnsupportedMessageType: u64 = 0;
    const EInvalidMessageType: u64 = 0;

    const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
    const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
    //const MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;

    public fun get_interchain_transfer_info(payload: vector<u8>): (TokenId, address, u64, vector<u8>) {
        let mut reader = abi::new_reader(payload);
        assert!(reader.read_u256() == MESSAGE_TYPE_INTERCHAIN_TRANSFER, EInvalidMessageType);

        let token_id = token_id::from_u256(reader.read_u256());
        let _source_address = reader.read_bytes();
        let destination = address::from_bytes(reader.read_bytes());
        let amount = (reader.read_u256() as u64);
        let data = reader.read_bytes();

        (
            token_id,
            destination,
            amount,
            data,
        )
    }

    public fun register_transaction(self: &mut ITS, discovery: &mut RelayerDiscovery) {
        self.set_relayer_discovery_id(discovery);
        let mut arg = vector[0];
        arg.append(bcs::to_bytes(&object::id(self)));

        let arguments = vector[
            arg,
            vector[3]
        ];

        let function = discovery::new_function(
            package_id<ITS>(),
            ascii::string(b"discovery"),
            ascii::string(b"get_call_info")
        );

        let move_call = discovery::new_move_call(
            function,
            arguments,
            vector[],
        );

        discovery.register_transaction(self.channel(), discovery::new_transaction(
            false,
            vector[move_call],
        ));
    }

    public fun get_call_info(self: &ITS, payload: vector<u8>): Transaction {
        let mut reader = abi::new_reader(payload);
        let message_type = reader.read_u256();

        if (message_type == MESSAGE_TYPE_INTERCHAIN_TRANSFER) {
            get_interchain_transfer_tx(self, &mut reader)
        } else {
            assert!(message_type == MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, EUnsupportedMessageType);
            get_deploy_interchain_token_tx(self, &mut reader)
        }
    }

    fun get_interchain_transfer_tx(self: &ITS, reader: &mut AbiReader): Transaction {
        let token_id = token_id::from_u256(reader.read_u256());
        let _source_address = reader.read_bytes();
        let destination_address = address::from_bytes(reader.read_bytes());
        let _amount = (reader.read_u256() as u64);
        let data = reader.read_bytes();

        if (data.is_empty()) {
            let mut arg = vector[0];
            arg.append(address::to_bytes(object::id_address(self)));

            let type_name = self.get_registered_coin_type(token_id);

            let arguments = vector[
                arg,
                vector[2]
            ];


            discovery::new_transaction(
                true,
                vector[discovery::new_move_call(
                    discovery::new_function(
                        package_id<ITS>(),
                        ascii::string(b"service"),
                        ascii::string(b"receive_interchain_transfer")
                    ),
                    arguments,
                    vector[ type_name::into_string(*type_name) ],
                )],
            )
        } else {
            let mut discovery_arg = vector[0];
            discovery_arg.append(self.relayer_discovery_id().id_to_address().to_bytes());

            let mut channel_id_arg = vector[1];
            channel_id_arg.append(destination_address.to_bytes());

            discovery::new_transaction(
                false,
                vector[discovery::new_move_call(
                    discovery::new_function(
                        package_id<RelayerDiscovery>(),
                        ascii::string(b"discovery"),
                        ascii::string(b"get_transaction")
                    ),
                    vector[
                        discovery_arg,
                        channel_id_arg,
                    ],
                    vector[],
                )],
            )
        }
    }

    fun get_deploy_interchain_token_tx(self: &ITS, reader: &mut AbiReader): Transaction {
        let mut arg = vector[0];
        arg.append(address::to_bytes(object::id_address(self)));

        let arguments = vector[
            arg,
            vector[2]
        ];

        let _token_id = token_id::from_u256(reader.read_u256());
        let _name = reader.read_bytes();
        let symbol = ascii::string(reader.read_bytes());
        let decimals = (reader.read_u256() as u8);
        let _distributor = address::from_bytes(reader.read_bytes());

        let type_name = self.get_unregistered_coin_type(&symbol, decimals);

        let move_call = discovery::new_move_call(
            discovery::new_function(
                package_id<ITS>(),
                ascii::string(b"service"),
                ascii::string(b"receive_deploy_interchain_token")
            ),
            arguments,
            vector[ type_name::into_string(*type_name) ],
        );

        discovery::new_transaction(
            true,
            vector[ move_call ],
        )
    }

    #[test_only]
    fun get_initial_tx(self: &ITS): Transaction {
        let mut arg = vector[0];
        arg.append(bcs::to_bytes(&object::id(self)));

        let arguments = vector[
            arg,
            vector[3]
        ];

        let function = discovery::new_function(
            discovery::package_id<ITS>(),
            ascii::string(b"discovery"),
            ascii::string(b"get_call_info")
        );

        let move_call = discovery::new_move_call(
            function,
            arguments,
            vector[],
        );

        discovery::new_transaction(
            false,
            vector[move_call],
        )
    }

    #[test]
    fun test_discovery_initial() {
        let ctx = &mut sui::tx_context::dummy();
        let mut its = its::its::new();
        let mut discovery = axelar_gateway::discovery::new(ctx);

        register_transaction(&mut its, &mut discovery);

        assert!(discovery.get_transaction(its.channel_id()) == get_initial_tx(&its), 0);
        assert!(its.relayer_discovery_id() == object::id(&discovery), 1);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(discovery);
    }

    #[test]
    fun test_discovery_interchain_transfer() {
        let ctx = &mut sui::tx_context::dummy();
        let mut its = its::its::new();
        let mut discovery = axelar_gateway::discovery::new(ctx);

        register_transaction(&mut its, &mut discovery);

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
        let tx_block = get_call_info(&its, payload);

        let mut reader = abi::new_reader(payload);
        let _message_type = reader.read_u256();

        assert!(tx_block == get_interchain_transfer_tx(&its, &mut reader), 1);
        assert!(tx_block.is_final() && tx_block.move_calls().length() == 1, 2);

        let call_info = tx_block.move_calls().pop_back();

        assert!(call_info.function().package_id_from_function() == package_id<ITS>(), 3);
        assert!(call_info.function().module_name() == ascii::string(b"service"), 4);
        assert!(call_info.function().name() == ascii::string(b"receive_interchain_transfer"), 5);
        let mut arg = vector[0];
        arg.append(address::to_bytes(object::id_address(&its)));

        let arguments = vector[
            arg,
            vector[2]
        ];
        assert!(call_info.arguments() == arguments, 6);
        assert!(call_info.type_arguments() == vector[type_arg.into_string()], 7);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(discovery);
    }

    #[test]
    fun test_discovery_interchain_transfer_with_data() {
        let ctx = &mut sui::tx_context::dummy();
        let mut its = its::its::new();
        let mut discovery = axelar_gateway::discovery::new(ctx);

        register_transaction(&mut its, &mut discovery);

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

        let mut reader = abi::new_reader(payload);
        let _message_type = reader.read_u256();

        assert!(get_call_info(&its, payload) == get_interchain_transfer_tx(&its, &mut reader), 1);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(discovery);
    }

    #[test]
    fun test_discovery_deploy_token() {
        let ctx = &mut sui::tx_context::dummy();
        let mut its = its::its::new();
        let mut discovery = axelar_gateway::discovery::new(ctx);

        register_transaction(&mut its, &mut discovery);

        let token_id = @0x1234;
        let name = b"name";
        let symbol = b"symbol";
        let decimals = 15;
        let distributor = @0x0325;
        let mut writer = abi::new_writer(6);
        writer
            .write_u256(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN)
            .write_u256(address::to_u256(token_id))
            .write_bytes(name)
            .write_bytes(symbol)
            .write_u256(decimals)
            .write_bytes(distributor.to_bytes());
        let payload = writer.into_bytes();

        let type_arg = std::type_name::get<RelayerDiscovery>();
        its.test_add_unregistered_coin_type(its::token_id::unregistered_token_id(&ascii::string(symbol), (decimals as u8)), type_arg);
        let tx_block = get_call_info(&its, payload);

        let mut reader = abi::new_reader(payload);
        let _message_type = reader.read_u256();

        assert!(tx_block == get_deploy_interchain_token_tx(&its, &mut reader), 1);

        assert!(tx_block.is_final(), 2);
        let mut move_calls = tx_block.move_calls();
        assert!(move_calls.length() == 1, 3);
        let call_info = move_calls.pop_back();
        assert!(call_info.function().package_id_from_function() == package_id<ITS>(), 4);
        assert!(call_info.function().module_name() == ascii::string(b"service"), 5);
        assert!(call_info.function().name() == ascii::string(b"receive_deploy_interchain_token"), 6);
        let mut arg = vector[0];
        arg.append(address::to_bytes(object::id_address(&its)));

        let arguments = vector[
            arg,
            vector[2]
        ];
        assert!(call_info.arguments() == arguments, 7);
        assert!(call_info.type_arguments() == vector[type_arg.into_string()], 8);

        sui::test_utils::destroy(its);
        sui::test_utils::destroy(discovery);
    }

}
