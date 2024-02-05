

module its::discovery {
    use std::ascii;
    use std::type_name;
    use std::vector;

    use sui::object;
    use sui::address;
    use sui::hex;
    use sui::bcs;

    use axelar::discovery::{Self, RelayerDiscovery, Transaction};
    use axelar::utils;

    use its::storage::{Self, ITS};
    use its::token_id;

    const EUnsupportedMessageType: u64 = 0;

    const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
    const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
    //const MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;

    public fun register_transaction(self: &ITS, discovery: &mut RelayerDiscovery) {
        let arg = vector[0];
        vector::append(&mut arg, bcs::to_bytes(&object::id(self)));

        let arguments = vector[
            arg,
            vector[3]
        ];

        let tx = discovery::new_transaction(
            discovery::new_function(
                address::from_bytes(hex::decode(*ascii::as_bytes(&type_name::get_address(&type_name::get<ITS>())))),
                ascii::string(b"discovery"),
                ascii::string(b"get_call_info")
            ),
            arguments,
            vector[],
        );

        discovery::register_transaction(discovery, storage::channel(self), tx);
    }

    public fun get_call_info(self: &ITS, payload: &vector<u8>): Transaction {
        let message_type = utils::abi_decode_fixed(payload, 0);
        if (message_type == MESSAGE_TYPE_INTERCHAIN_TRANSFER) {
            get_interchain_transfer_tx(self, payload)
        } else {
            assert!( message_type == MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, EUnsupportedMessageType );
            get_deploy_interchain_token_tx(self, payload)
        }
    }

    fun get_interchain_transfer_tx(self: &ITS, payload: &vector<u8>): Transaction {
        let data = utils::abi_decode_variable(payload, 5);

        if (vector::is_empty(&data)) {
            let arg = vector[0];
            vector::append(&mut arg, address::to_bytes(object::id_address(self)));

            let arguments = vector[
                arg,
                vector[2]
            ];

            let token_id = token_id::from_u256(utils::abi_decode_fixed(payload, 1));
            let type_name = storage::get_registered_coin_type(self, token_id);

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
            let transaction = utils::abi_decode_variable(&data, 0);
            discovery::new_transaction_from_bcs(&mut bcs::new(transaction))
        }
    }

    fun get_deploy_interchain_token_tx(self: &ITS, payload: &vector<u8>): Transaction {
        let arg = vector::singleton<u8>(0);
        vector::append(&mut arg, address::to_bytes(object::id_address(self)));

        let arguments = vector[
            arg,
            vector[2]
        ];

        let symbol = ascii::string(utils::abi_decode_variable(payload, 3));
        let decimals = (utils::abi_decode_fixed(payload, 4) as u8);
        let type_name = storage::get_unregistered_coin_type(self, &symbol, decimals);

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
