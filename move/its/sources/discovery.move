module its::discovery;

use abi::abi::{Self, AbiReader};
use its::its::ITS;
use its::token_id::{Self, TokenId};
use relayer_discovery::discovery::RelayerDiscovery;
use relayer_discovery::transaction::{Self, Transaction, package_id};
use std::ascii;
use std::type_name;
use sui::address;

const EUnsupportedMessageType: u64 = 0;
const EInvalidMessageType: u64 = 0;

const MESSAGE_TYPE_INTERCHAIN_TRANSFER: u256 = 0;
const MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN: u256 = 1;
// onst MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER: u256 = 2;
// onst MESSAGE_TYPE_SEND_TO_HUB: u256 = 3;
const MESSAGE_TYPE_RECEIVE_FROM_HUB: u256 = 4;

public fun interchain_transfer_info(
    payload: vector<u8>,
): (TokenId, address, u64, vector<u8>) {
    let mut reader = abi::new_reader(payload);
    assert!(
        reader.read_u256() == MESSAGE_TYPE_INTERCHAIN_TRANSFER,
        EInvalidMessageType,
    );

    let token_id = token_id::from_u256(reader.read_u256());
    reader.skip_slot(); // skip source_address
    let destination = address::from_bytes(reader.read_bytes());
    let amount = (reader.read_u256() as u64);
    let data = reader.read_bytes();

    (token_id, destination, amount, data)
}

public fun register_transaction(
    its: &mut ITS,
    discovery: &mut RelayerDiscovery,
) {
    let mut arg = vector[0];
    arg.append(object::id(its).to_bytes());

    let arguments = vector[arg, vector[3]];

    let function = transaction::new_function(
        package_id<ITS>(),
        ascii::string(b"discovery"),
        ascii::string(b"get_call_info"),
    );

    let move_call = transaction::new_move_call(
        function,
        arguments,
        vector[],
    );

    its.register_transaction(
        discovery,
        transaction::new_transaction(
            false,
            vector[move_call],
        ),
    );
}

public fun call_info(its: &ITS, mut payload: vector<u8>): Transaction {
    let mut reader = abi::new_reader(payload);
    let mut message_type = reader.read_u256();

    if (message_type == MESSAGE_TYPE_RECEIVE_FROM_HUB) {
        reader.skip_slot();
        payload = reader.read_bytes();
        reader = abi::new_reader(payload);
        message_type = reader.read_u256();
    };

    if (message_type == MESSAGE_TYPE_INTERCHAIN_TRANSFER) {
        interchain_transfer_tx(its, &mut reader)
    } else {
        assert!(
            message_type == MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN,
            EUnsupportedMessageType,
        );
        deploy_interchain_token_tx(its, &mut reader)
    }
}

fun interchain_transfer_tx(its: &ITS, reader: &mut AbiReader): Transaction {
    let token_id = token_id::from_u256(reader.read_u256());
    reader.skip_slot(); // skip source_address
    let destination_address = address::from_bytes(reader.read_bytes());
    reader.skip_slot(); // skip amount
    let data = reader.read_bytes();
    let value = its.package_value();

    if (data.is_empty()) {
        let mut arg = vector[0];
        arg.append(object::id_address(its).to_bytes());

        let type_name = value.registered_coin_type(token_id);

        let arguments = vector[arg, vector[2], vector[0, 6]];

        transaction::new_transaction(
            true,
            vector[
                transaction::new_move_call(
                    transaction::new_function(
                        package_id<ITS>(),
                        ascii::string(b"service"),
                        ascii::string(b"receive_interchain_transfer"),
                    ),
                    arguments,
                    vector[type_name::into_string(*type_name)],
                ),
            ],
        )
    } else {
        let mut discovery_arg = vector[0];
        discovery_arg.append(value
            .relayer_discovery_id()
            .id_to_address()
            .to_bytes());

        let mut channel_id_arg = vector[1];
        channel_id_arg.append(destination_address.to_bytes());

        transaction::new_transaction(
            false,
            vector[
                transaction::new_move_call(
                    transaction::new_function(
                        package_id<RelayerDiscovery>(),
                        ascii::string(b"discovery"),
                        ascii::string(b"get_transaction"),
                    ),
                    vector[discovery_arg, channel_id_arg, vector[0, 6]],
                    vector[],
                ),
            ],
        )
    }
}

fun deploy_interchain_token_tx(its: &ITS, reader: &mut AbiReader): Transaction {
    let mut arg = vector[0];
    arg.append(object::id_address(its).to_bytes());

    let arguments = vector[arg, vector[2]];

    reader.skip_slot(); // skip token_id
    reader.skip_slot(); // skip _name
    let symbol = ascii::string(reader.read_bytes());
    let decimals = (reader.read_u256() as u8);
    reader.skip_slot(); // skip distributor

    let value = its.package_value();
    let type_name = value.unregistered_coin_type(&symbol, decimals);

    let move_call = transaction::new_move_call(
        transaction::new_function(
            package_id<ITS>(),
            ascii::string(b"service"),
            ascii::string(b"receive_deploy_interchain_token"),
        ),
        arguments,
        vector[type_name::into_string(*type_name)],
    );

    transaction::new_transaction(
        true,
        vector[move_call],
    )
}

// === Tests ===
#[test_only]
fun initial_tx(its: &ITS): Transaction {
    let mut arg = vector[0];
    arg.append(sui::bcs::to_bytes(&object::id(its)));

    let arguments = vector[arg, vector[3]];

    let function = transaction::new_function(
        package_id<ITS>(),
        ascii::string(b"discovery"),
        ascii::string(b"get_call_info"),
    );

    let move_call = transaction::new_move_call(
        function,
        arguments,
        vector[],
    );

    transaction::new_transaction(
        false,
        vector[move_call],
    )
}

#[test]
fun test_discovery_initial() {
    let ctx = &mut sui::tx_context::dummy();
    let mut its = its::its::create_for_testing(ctx);
    let mut discovery = relayer_discovery::discovery::new(ctx);

    register_transaction(&mut its, &mut discovery);

    let value = its.package_value();
    assert!(
        discovery.get_transaction(object::id_from_address(value.channel_address())) == initial_tx(&its),
    );
    assert!(value.relayer_discovery_id() == object::id(&discovery));

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(discovery);
}

#[test]
fun test_discovery_interchain_transfer() {
    let ctx = &mut sui::tx_context::dummy();
    let mut its = its::its::create_for_testing(ctx);
    let mut discovery = relayer_discovery::discovery::new(ctx);

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
        .write_bytes(target_channel.to_bytes())
        .write_u256(amount)
        .write_bytes(data);
    let payload = writer.into_bytes();

    let type_arg = std::type_name::get<RelayerDiscovery>();
    its.add_registered_coin_type_for_testing(
        its::token_id::from_address(token_id),
        type_arg,
    );
    let tx_block = call_info(&its, payload);

    let mut reader = abi::new_reader(payload);
    reader.skip_slot(); // skip message_type

    assert!(tx_block == interchain_transfer_tx(&its, &mut reader));
    assert!(tx_block.is_final() && tx_block.move_calls().length() == 1);

    let call_info = tx_block.move_calls().pop_back();

    assert!(
        call_info.function().package_id_from_function() == package_id<ITS>(),
    );
    assert!(call_info.function().module_name() == ascii::string(b"service"));
    assert!(
        call_info.function().name() == ascii::string(b"receive_interchain_transfer"),
    );
    let mut arg = vector[0];
    arg.append(object::id_address(&its).to_bytes());

    let arguments = vector[arg, vector[2], vector[0, 6]];
    assert!(call_info.arguments() == arguments);
    assert!(call_info.type_arguments() == vector[type_arg.into_string()]);

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(discovery);
}

#[test]
fun test_discovery_interchain_transfer_with_data() {
    let ctx = &mut sui::tx_context::dummy();
    let mut its = its::its::create_for_testing(ctx);
    let mut discovery = relayer_discovery::discovery::new(ctx);

    register_transaction(&mut its, &mut discovery);

    assert!(
        discovery.get_transaction(object::id_from_address(its.package_value().channel_address())) == initial_tx(&its),
    );

    let token_id = @0x1234;
    let source_address = b"source address";
    let target_channel = @0x5678;
    let amount = 1905;
    let tx_data = sui::bcs::to_bytes(&initial_tx(&its));
    let mut writer = abi::new_writer(2);
    writer.write_bytes(tx_data).write_u256(1245);
    let data = writer.into_bytes();

    writer = abi::new_writer(6);
    writer
        .write_u256(MESSAGE_TYPE_INTERCHAIN_TRANSFER)
        .write_u256(address::to_u256(token_id))
        .write_bytes(source_address)
        .write_bytes(target_channel.to_bytes())
        .write_u256(amount)
        .write_bytes(data);
    let payload = writer.into_bytes();

    its.add_registered_coin_type_for_testing(
        its::token_id::from_address(token_id),
        std::type_name::get<RelayerDiscovery>(),
    );

    let mut reader = abi::new_reader(payload);
    reader.skip_slot(); // skip message_type

    assert!(
        call_info(&its, payload) == interchain_transfer_tx(&its, &mut reader),
    );

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(discovery);
}

#[test]
fun test_discovery_deploy_token() {
    let ctx = &mut sui::tx_context::dummy();
    let mut its = its::its::create_for_testing(ctx);
    let mut discovery = relayer_discovery::discovery::new(ctx);

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
    its.add_unregistered_coin_type_for_testing(
        its::token_id::unregistered_token_id(
            &ascii::string(symbol),
            (decimals as u8),
        ),
        type_arg,
    );
    let tx_block = call_info(&its, payload);

    let mut reader = abi::new_reader(payload);
    reader.skip_slot(); // skip message_type

    assert!(tx_block == deploy_interchain_token_tx(&its, &mut reader));

    assert!(tx_block.is_final());
    let mut move_calls = tx_block.move_calls();
    assert!(move_calls.length() == 1);
    let call_info = move_calls.pop_back();
    assert!(
        call_info.function().package_id_from_function() == package_id<ITS>(),
    );
    assert!(call_info.function().module_name() == ascii::string(b"service"));
    assert!(
        call_info.function().name() == ascii::string(b"receive_deploy_interchain_token"),
    );
    let mut arg = vector[0];
    arg.append(object::id_address(&its).to_bytes());

    let arguments = vector[arg, vector[2]];
    assert!(call_info.arguments() == arguments);
    assert!(call_info.type_arguments() == vector[type_arg.into_string()]);

    sui::test_utils::destroy(its);
    sui::test_utils::destroy(discovery);
}
