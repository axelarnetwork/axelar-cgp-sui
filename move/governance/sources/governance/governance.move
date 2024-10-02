module governance::governance;

use abi::abi;
use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
use std::ascii::String;
use std::type_name;
use sui::address;
use sui::hex;
use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
use sui::table::{Self, Table};

#[error]
const EUntrustedAddress: vector<u8> =
    b"upgrade authorization attempt from an untrusted address";

#[error]
const EInvalidMessageType: vector<u8> =
    b"invalid message type for upgrade authorization";

#[error]
const ENotSelfUpgradeCap: vector<u8> =
    b"governance initialization requires its own upgrade capability. The provided capability belongs to a different package";

#[error]
const ENotNewPackage: vector<u8> = b"Not new package.";

public struct Governance has key, store {
    id: UID,
    trusted_source_chain: String,
    trusted_source_address: String,
    message_type: u256,
    channel: Channel,
    caps: Table<ID, UpgradeCap>,
}

// This can only be called once since it needs its own upgrade cap which it deletes.
entry fun new(
    trusted_source_chain: String,
    trusted_source_address: String,
    message_type: u256,
    upgrade_cap: UpgradeCap,
    ctx: &mut TxContext,
) {
    let package_id = object::id_from_bytes(
        hex::decode(type_name::get<Governance>().get_address().into_bytes()),
    );
    assert!(upgrade_cap.upgrade_package() == package_id, ENotSelfUpgradeCap);
    is_cap_new(&upgrade_cap);
    package::make_immutable(upgrade_cap);

    transfer::share_object(Governance {
        id: object::new(ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type,
        channel: channel::new(ctx),
        caps: table::new<ID, UpgradeCap>(ctx),
    })
}

public fun is_governance(
    self: &Governance,
    chain_name: String,
    addr: String,
): bool {
    &chain_name ==
    &self.trusted_source_chain &&
    &addr == &self.trusted_source_address
}

// TODO maybe check that the polcy for the upgrade cap has not been tampered with.
entry fun take_upgrade_cap(self: &mut Governance, upgrade_cap: UpgradeCap) {
    is_cap_new(&upgrade_cap);

    self
        .caps
        .add(
            object::id(&upgrade_cap),
            upgrade_cap,
        )
}

public fun authorize_upgrade(
    self: &mut Governance,
    approved_message: ApprovedMessage,
): UpgradeTicket {
    let (source_chain, _, source_address, payload) = self
        .channel
        .consume_approved_message(approved_message);

    assert!(
        is_governance(self, source_chain, source_address),
        EUntrustedAddress,
    );

    let mut abi = abi::new_reader(payload);
    let message_type = abi.read_u256();
    assert!(message_type == self.message_type, EInvalidMessageType);

    let cap_id = object::id_from_address(address::from_u256(abi.read_u256()));
    let policy = abi.read_u8();
    let digest = abi.read_bytes();

    package::authorize_upgrade(
        table::borrow_mut(&mut self.caps, cap_id),
        policy,
        digest,
    )
}

public fun commit_upgrade(self: &mut Governance, receipt: UpgradeReceipt) {
    package::commit_upgrade(
        table::borrow_mut(
            &mut self.caps,
            package::receipt_cap(&receipt),
        ),
        receipt,
    )
}

fun is_cap_new(cap: &UpgradeCap) {
    assert!(package::version(cap) == 1, ENotNewPackage);
}

// -----
// Tests
// -----

#[test_only]
use std::ascii;
#[test_only]
use sui::test_scenario;
#[test_only]
use sui::test_utils;

#[test_only]
public fun new_for_testing(
    trusted_source_chain: String,
    trusted_source_address: String,
    message_type: u256,
    ctx: &mut TxContext,
): Governance {
    Governance {
        id: object::new(ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type,
        channel: channel::new(ctx),
        caps: table::new<ID, UpgradeCap>(ctx),
    }
}

#[test]
fun test_new() {
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let message_type = 2;
    let mut ctx = tx_context::dummy();
    let package_id = object::id_from_bytes(
        hex::decode(type_name::get<Governance>().get_address().into_bytes()),
    );
    let upgrade_cap = package::test_publish(package_id, &mut ctx);
    let initial_owner = @0x1;
    let mut scenario = test_scenario::begin(initial_owner);
    {
        test_scenario::sender(&scenario);
        new(
            trusted_source_chain,
            trusted_source_address,
            message_type,
            upgrade_cap,
            &mut ctx,
        );
    };

    test_scenario::next_tx(&mut scenario, initial_owner);
    {
        let governance = test_scenario::take_shared<Governance>(&scenario);
        test_scenario::return_shared(governance);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = test_scenario::EEmptyInventory)]
fun test_new_immutable_upgrade() {
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let message_type = 2;
    let mut ctx = tx_context::dummy();
    let package_id = object::id_from_bytes(
        hex::decode(type_name::get<Governance>().get_address().into_bytes()),
    );
    let upgrade_cap = package::test_publish(package_id, &mut ctx);
    let initial_owner = @0x1;
    let mut scenario = test_scenario::begin(initial_owner);
    {
        test_scenario::sender(&scenario);
        new(
            trusted_source_chain,
            trusted_source_address,
            message_type,
            upgrade_cap,
            &mut ctx,
        );
    };

    test_scenario::next_tx(&mut scenario, initial_owner);
    {
        let upgrade_cap = test_scenario::take_shared<UpgradeCap>(&scenario);
        test_scenario::return_shared(upgrade_cap);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = ENotSelfUpgradeCap)]
fun test_new_incorrect_upgrade_cap() {
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let message_type = 2;
    let mut ctx = tx_context::dummy();
    let uid = object::new(&mut ctx);
    let upgrade_cap = package::test_publish(
        object::uid_to_inner(&uid),
        &mut ctx,
    );
    new(
        trusted_source_chain,
        trusted_source_address,
        message_type,
        upgrade_cap,
        &mut ctx,
    );

    test_utils::destroy(uid);
}

#[test]
fun test_is_governance() {
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let message_type = 2;
    let mut ctx = tx_context::dummy();

    let governance = Governance {
        id: object::new(&mut ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type,
        channel: channel::new(&mut ctx),
        caps: table::new<ID, UpgradeCap>(&mut ctx),
    };

    assert!(
        governance.is_governance(trusted_source_chain, trusted_source_address),
        1,
    );

    test_utils::destroy(governance);
}

#[test]
fun test_is_governance_false_argument() {
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let message_type = 2;
    let mut ctx = tx_context::dummy();

    let governance = Governance {
        id: object::new(&mut ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type,
        channel: channel::new(&mut ctx),
        caps: table::new<ID, UpgradeCap>(&mut ctx),
    };

    assert!(
        !governance.is_governance(
            ascii::string(b"sui"),
            trusted_source_address,
        ),
        1,
    );

    test_utils::destroy(governance);
}

#[test]
fun test_is_cap_new() {
    let mut ctx = tx_context::dummy();
    let uid = object::new(&mut ctx);
    let upgrade_cap = package::test_publish(
        object::uid_to_inner(&uid),
        &mut ctx,
    );
    is_cap_new(&upgrade_cap);

    test_utils::destroy(uid);
    test_utils::destroy(upgrade_cap);
}

#[test]
#[expected_failure(abort_code = ENotNewPackage)]
fun test_is_cap_new_upgrade_version() {
    let mut ctx = tx_context::dummy();
    let uid = object::new(&mut ctx);
    let mut upgrade_cap = package::test_publish(
        object::uid_to_inner(&uid),
        &mut ctx,
    );
    let upgrade_ticket = package::authorize_upgrade(&mut upgrade_cap, 2, b"");
    let upgrade_reciept = package::test_upgrade(upgrade_ticket);
    package::commit_upgrade(&mut upgrade_cap, upgrade_reciept);
    is_cap_new(&upgrade_cap);

    test_utils::destroy(uid);
    test_utils::destroy(upgrade_cap);
}

#[test]
fun test_take_upgrade_cap() {
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let message_type = 2;
    let mut ctx = tx_context::dummy();
    let package_id = object::id_from_bytes(
        hex::decode(type_name::get<Governance>().get_address().into_bytes()),
    );
    let upgrade_cap = package::test_publish(package_id, &mut ctx);
    let initial_owner = @0x1;
    let mut scenario = test_scenario::begin(initial_owner);
    {
        test_scenario::sender(&scenario);
        new(
            trusted_source_chain,
            trusted_source_address,
            message_type,
            upgrade_cap,
            &mut ctx,
        );
    };

    test_scenario::next_tx(&mut scenario, initial_owner);
    {
        let mut governance = test_scenario::take_shared<Governance>(&scenario);
        let upgrade_cap = package::test_publish(package_id, &mut ctx);
        let upgrade_id = object::id(&upgrade_cap);
        take_upgrade_cap(&mut governance, upgrade_cap);
        let recieved_upgrade_cap = table::borrow_mut(
            &mut governance.caps,
            upgrade_id,
        );
        assert!(object::id(recieved_upgrade_cap) == upgrade_id);
        test_scenario::return_shared(governance);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_commit_upgrade() {
    let mut ctx = tx_context::dummy();
    let uid = object::new(&mut ctx);
    let mut upgrade_cap = package::test_publish(
        object::uid_to_inner(&uid),
        &mut ctx,
    );
    let upgrade_ticket = package::authorize_upgrade(&mut upgrade_cap, 2, b"");
    let upgrade_reciept = package::test_upgrade(upgrade_ticket);
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let message_type = 2;
    let mut governance = Governance {
        id: object::new(&mut ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type,
        channel: channel::new(&mut ctx),
        caps: table::new<ID, UpgradeCap>(&mut ctx),
    };
    let upgrade_id = object::id(&upgrade_cap);
    take_upgrade_cap(&mut governance, upgrade_cap);
    commit_upgrade(&mut governance, upgrade_reciept);
    let upgrade_cap_return = table::borrow(
        &governance.caps,
        upgrade_id,
    );
    assert!(upgrade_id == object::id(upgrade_cap_return));
    assert!(package::version(upgrade_cap_return) == 2);
    test_utils::destroy(uid);
    test_utils::destroy(governance);
}

#[test]
fun test_authorize_upgrade() {
    let mut ctx = tx_context::dummy();
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let channale_object = channel::new(&mut ctx);
    let payload =
        x"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010400000000000000000000000000000000000000000000000000000000000000";
    let mut abi = abi::new_reader(payload);
    let message_type = abi.read_u256();
    let uid = object::new(&mut ctx);
    let upgrade_cap = package::test_publish(
        object::uid_to_inner(&uid),
        &mut ctx,
    );
    let cap_id = object::id_from_address(address::from_u256(abi.read_u256()));
    let approved_message = channel::new_approved_message(
        trusted_source_chain,
        ascii::string(b"1"),
        trusted_source_address,
        object::id_address(&channale_object),
        payload,
    );
    let mut governance = Governance {
        id: object::new(&mut ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type: message_type,
        channel: channale_object,
        caps: table::new<ID, UpgradeCap>(&mut ctx),
    };

    governance
        .caps
        .add(
            cap_id,
            upgrade_cap,
        );
    let upgrade_ticket = authorize_upgrade(&mut governance, approved_message);
    assert!(
        package::ticket_package(&upgrade_ticket) == object::uid_to_inner(&uid),
        1,
    );
    let policy = abi.read_u8();
    assert!(package::ticket_policy(&upgrade_ticket) == policy);
    let digest = abi.read_bytes();
    assert!(package::ticket_digest(&upgrade_ticket) == digest);
    test_utils::destroy(upgrade_ticket);
    test_utils::destroy(uid);
    test_utils::destroy(governance);
}

#[test]
#[expected_failure(abort_code = EInvalidMessageType)]
fun test_authorize_upgrade_invalid_message_type() {
    let mut ctx = tx_context::dummy();
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let channale_object = channel::new(&mut ctx);
    let payload =
        x"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0";
    let approved_message = channel::new_approved_message(
        trusted_source_chain,
        ascii::string(b"1"),
        trusted_source_address,
        object::id_address(&channale_object),
        payload,
    );
    let mut governance = Governance {
        id: object::new(&mut ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type: 2,
        channel: channale_object,
        caps: table::new<ID, UpgradeCap>(&mut ctx),
    };
    let upgrade_ticket = authorize_upgrade(&mut governance, approved_message);
    test_utils::destroy(upgrade_ticket);
    test_utils::destroy(governance);
}

#[test]
#[expected_failure(abort_code = EUntrustedAddress)]
fun test_authorize_upgrade_trusted_address() {
    let mut ctx = tx_context::dummy();
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let channale_object = channel::new(&mut ctx);
    let payload =
        x"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0";
    let approved_message = channel::new_approved_message(
        ascii::string(b"sui"),
        ascii::string(b"1"),
        ascii::string(b"0x1"),
        object::id_address(&channale_object),
        payload,
    );
    let mut governance = Governance {
        id: object::new(&mut ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type: 2,
        channel: channale_object,
        caps: table::new<ID, UpgradeCap>(&mut ctx),
    };
    let upgrade_ticket = authorize_upgrade(&mut governance, approved_message);
    test_utils::destroy(upgrade_ticket);
    test_utils::destroy(governance);
}

#[test]
#[expected_failure(abort_code = channel::EInvalidDestination)]
fun test_authorize_invalid_destination_address() {
    let mut ctx = tx_context::dummy();
    let trusted_source_chain = ascii::string(b"Axelar");
    let trusted_source_address = ascii::string(b"0x0");
    let channale_object = channel::new(&mut ctx);
    let payload = x"01";
    let approved_message = channel::new_approved_message(
        ascii::string(b"sui"),
        ascii::string(b"1"),
        ascii::string(b"0x1"),
        address::from_u256(2),
        payload,
    );
    let mut governance = Governance {
        id: object::new(&mut ctx),
        trusted_source_chain,
        trusted_source_address,
        message_type: 2,
        channel: channale_object,
        caps: table::new<ID, UpgradeCap>(&mut ctx),
    };
    let upgrade_ticket = authorize_upgrade(&mut governance, approved_message);
    test_utils::destroy(upgrade_ticket);
    test_utils::destroy(governance);
}
