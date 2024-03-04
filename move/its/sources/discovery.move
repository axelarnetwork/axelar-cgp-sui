

module its::discovery {
    use std::ascii;
    use std::type_name;
    use std::vector;

    use sui::object;
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
            address_bytes<ITS>(),
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

    public fun get_call_info(self: &ITS, payload: vector<u8>): Transaction {
        let reader = abi::new_reader(payload);
        let message_type = reader.read_u256(0);
        if (message_type == MESSAGE_TYPE_INTERCHAIN_TRANSFER) {
            get_interchain_transfer_tx(self, &reader)
        } else {
            assert!(message_type == MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, EUnsupportedMessageType);
            get_deploy_interchain_token_tx(self, &reader)
        }
    }

    fun get_interchain_transfer_tx(self: &ITS, reader: &AbiReader): Transaction {
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

            discovery::new_transaction(
                discovery::new_function(
                    address_bytes<ITS>(),
                    ascii::string(b"service"),
                    ascii::string(b"receive_interchain_transfer")
                ),
                arguments,
                vector[ type_name::into_string(*type_name) ],
            )
        } else {
            let transaction = abi::new_reader(data).read_bytes(0);
            discovery::new_transaction_from_bcs(&mut bcs::new(transaction))
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
                address_bytes<ITS>(),
                ascii::string(b"service"),
                ascii::string(b"receive_deploy_interchain_token")
            ),
            arguments,
            vector[ type_name::into_string(*type_name) ],
        )
    }

    /// Returns the address of the ITS module (from the type name).
    fun address_bytes<ITS>(): address {
        address::from_bytes(
            hex::decode(
                *ascii::as_bytes(
                    &type_name::get_address(&type_name::get<ITS>())
                )
            )
        )
    }
}
