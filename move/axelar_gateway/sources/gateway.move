/// Implementation of the Axelar Gateway for Sui Move.
///
/// This code is based on the following:
///
/// - When call approvals is sent to Sui, it targets an object and not a module;
/// - To support cross-chain messaging, a Channel object has to be created;
/// - Channel can be either owned or shared but not frozen;
/// - Module developer on the Sui side will have to implement a system to support messaging;
/// - Checks for uniqueness of approvals should be done through `Channel`s to avoid big value storage;
///
/// I. Sending call approvals
///
/// A approval is sent through the `send` function, a Channel is supplied to determine the source -> ID.
/// Event is then emitted and Axelar network can operate
///
/// II. Receiving call approvals
///
/// Approval bytes and signatures are passed into `create` function to generate a CallApproval object.
///  - Signatures are checked against the known set of signers.
///  - CallApproval bytes are parsed to determine: source, destination_chain, payload and destination_id
///  - `destination_id` points to a `Channel` object
///
/// Once created, `CallApproval` needs to be consumed. And the only way to do it is by calling
/// `consume_call_approval` function and pass a correct `Channel` instance alongside the `CallApproval`.
///  - CallApproval is checked for uniqueness (for this channel)
///  - CallApproval is checked to match the `Channel`.id
///
/// The Gateway object uses a versioned field to support upgradability. The current implementation uses Gateway_v0.
module axelar_gateway::gateway;

use axelar_gateway::auth::{Self, validate_proof};
use axelar_gateway::bytes32::{Self, Bytes32};
use axelar_gateway::channel::{Channel, ApprovedMessage};
use axelar_gateway::weighted_signers;
use axelar_gateway::message_ticket::{Self, MessageTicket};
use axelar_gateway::gateway_v0::{Self, Gateway_v0};
use std::ascii::{Self, String};
use sui::clock::Clock;
use sui::table::{Self};
use sui::versioned::{Self, Versioned};
use version_control::version_control::{Self, VersionControl};
use utils::utils;

// -------
// Version
// -------
const VERSION: u64 = 0;

// -------
// Structs
// -------
public struct Gateway has key {
    id: UID,
    inner: Versioned,
}

// ------------
// Capabilities
// ------------
public struct CreatorCap has key, store {
    id: UID,
}

// -----
// Setup
// -----

/// Init the module by giving a CreatorCap to the sender to allow a full `setup`.
fun init(ctx: &mut TxContext) {
    let cap = CreatorCap {
        id: object::new(ctx),
    };

    transfer::transfer(cap, ctx.sender());
}

/// Setup the module by creating a new Gateway object.
entry fun setup(
    cap: CreatorCap,
    operator: address,
    domain_separator: address,
    minimum_rotation_delay: u64,
    previous_signers_retention: u64,
    initial_signers: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let CreatorCap { id } = cap;
    id.delete();

    let inner = versioned::create(
        VERSION,
        gateway_v0::new(
            operator,
            table::new(ctx),
            auth::setup(
                bytes32::new(domain_separator),
                minimum_rotation_delay,
                previous_signers_retention,
                utils::peel!(
                    initial_signers,
                    |bcs| weighted_signers::peel(bcs),
                ),
                clock,
                ctx,
            ),
            version_control(),
        ),
        ctx,
    );

    // Share the gateway object for anyone to use.
    transfer::share_object(Gateway {
        id: object::new(ctx),
        inner,
    });
}

// ------
// Macros
// ------
/// This macro also uses version control to sinplify things a bit.
macro fun value($self: &Gateway, $function_name: vector<u8>): &Gateway_v0 {
    let gateway = $self;
    let value = gateway.inner.load_value<Gateway_v0>();
    value.version_control().check(VERSION, ascii::string($function_name));
    value
}

/// This macro also uses version control to sinplify things a bit.
macro fun value_mut($self: &mut Gateway, $function_name: vector<u8>): &mut Gateway_v0 {
    let gateway = $self;
    let value = gateway.inner.load_value_mut<Gateway_v0>();
    value.version_control().check(VERSION, ascii::string($function_name));
    value
}

// -----------
// Entrypoints
// -----------

/// The main entrypoint for approving Axelar signed messages.
/// If proof is valid, message approvals are stored in the Gateway object, if not already approved before.
/// This method is only intended to be called via a Transaction Block, keeping more flexibility for upgrades.
entry fun approve_messages(
    self: &mut Gateway,
    message_data: vector<u8>,
    proof_data: vector<u8>,
) {
    let value = self.value_mut!(b"approve_messages");
    value.approve_messages(message_data, proof_data);
}

/// The main entrypoint for rotating Axelar signers.
/// If proof is valid, signers stored on the Gateway object are rotated.
/// This method is only intended to be called via a Transaction Block, keeping more flexibility for upgrades.
entry fun rotate_signers(
    self: &mut Gateway,
    clock: &Clock,
    new_signers_data: vector<u8>,
    proof_data: vector<u8>,
    ctx: &TxContext,
) {
    let value = self.value_mut!(b"rotate_signers");
    value.rotate_signers(
        clock,
        new_signers_data,
        proof_data,
        ctx,
    )
}

// ----------------
// Public Functions
// ----------------

/// Prepare a MessageTicket to call a contract on the destination chain.
public fun prepare_message(
    channel: &Channel,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
): MessageTicket {
    message_ticket::new(
        channel.to_address(),
        destination_chain,
        destination_address,
        payload,
        VERSION,
    )
}

/// Submit the MessageTicket which causes a contract call by sending an event from an
/// authorized Channel.
public fun send_message(
    self: &Gateway,
    message: MessageTicket,
) {
    let value = self.value!(b"send_message");
    value.send_message(message, VERSION);
}

public fun is_message_approved(
    self: &Gateway,
    source_chain: String,
    message_id: String,
    source_address: String,
    destination_id: address,
    payload_hash: Bytes32,
): bool {
    let value = self.value!(b"is_message_approved");
    value.is_message_approved(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload_hash,
    )
}

public fun is_message_executed(
    self: &Gateway,
    source_chain: String,
    message_id: String,
): bool {
    let value = self.value!(b"is_message_executed");
    value.is_message_executed(source_chain, message_id)
}

/// To execute a message, the relayer will call `take_approved_message`
/// to get the hot potato `ApprovedMessage` object, and then trigger the app's package via discovery.
public fun take_approved_message(
    self: &mut Gateway,
    source_chain: String,
    message_id: String,
    source_address: String,
    destination_id: address,
    payload: vector<u8>,
): ApprovedMessage {
    let value = self.value_mut!(b"take_approved_message");
    value.take_approved_message(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    )
}

// -----------------
// Private Functions
// -----------------

fun version_control(): VersionControl {
    version_control::new(
        vector [
            // Version 0
            vector [
                b"approve_messages",
                b"rotate_signers",
                b"is_message_approved",
                b"is_message_executed",
                b"take_approved_message",
                b"send_message",
            ].map!(|function_name| function_name.to_ascii_string())
        ]
    )
}

// ---------
// Test Only
// ---------
#[test_only]
use sui::bcs;
#[test_only]
use axelar_gateway::auth::generate_proof;

#[test_only]
public fun create_for_testing(
    operator: address,
    domain_separator: Bytes32,
    minimum_rotation_delay: u64,
    previous_signers_retention: u64,
    initial_signers: weighted_signers::WeightedSigners,
    clock: &Clock,
    ctx: &mut TxContext,
): Gateway {
    let inner = versioned::create(
        VERSION,
        gateway_v0::new(
            operator,
            table::new(ctx),
            auth::setup(
                domain_separator,
                minimum_rotation_delay,
                previous_signers_retention,
                initial_signers,
                clock,
                ctx,
            ),
            version_control(),
        ),
        ctx,
    );
    Gateway {
        id: object::new(ctx),
        inner,
    }
}

#[test_only]
fun dummy(ctx: &mut TxContext): Gateway {
    let inner = versioned::create(
        VERSION,
        gateway_v0::new(
            @0x0,
            table::new(ctx),
            auth::dummy(ctx),
            version_control::new(
                vector [
                    // Version 0
                    vector [
                        b"approve_messages",
                        b"rotate_signers",
                        b"is_message_approved",
                        b"is_message_executed",
                        b"take_approved_message",
                        b"send_message",
                        b"",
                    ].map!(|function_name| function_name.to_ascii_string())
                ]
            )
        ),
        ctx,
    );
    Gateway {
        id: object::new(ctx),
        inner,
    }
}

#[test_only]
public fun destroy_for_testing(self: Gateway) {
    let Gateway {
        id,
        inner,
    } = self;
    id.delete();

    let value = inner.destroy<Gateway_v0>();
    let (
        _,
        messages,
        signers,
        _,
    ) = value.destroy_for_testing();

    let (_, table, _, _, _, _) = signers.destroy_for_testing();
    table.destroy_empty();
    messages.destroy_empty();
}

// ----
// Test
// ----
#[test]
fun test_init() {
    let mut ts = sui::test_scenario::begin(@0x0);

    init(ts.ctx());
    ts.next_tx(@0x0);

    let creator_cap = ts.take_from_sender<CreatorCap>();
    ts.return_to_sender(creator_cap);
    ts.end();
}

#[test]
fun test_setup() {
    let ctx = &mut sui::tx_context::dummy();
    let operator = @123456;
    let domain_separator = @789012;
    let minimum_rotation_delay = 765;
    let previous_signers_retention = 650;
    let initial_signers = axelar_gateway::weighted_signers::dummy();
    let mut clock = sui::clock::create_for_testing(ctx);
    let timestamp = 1234;
    clock.increment_for_testing(timestamp);

    let creator_cap = CreatorCap {
        id: object::new(ctx),
    };

    let mut scenario = sui::test_scenario::begin(@0x1);

    setup(
        creator_cap,
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        bcs::to_bytes(&initial_signers),
        &clock,
        scenario.ctx(),
    );

    let tx_effects = scenario.next_tx(@0x1);
    let shared = tx_effects.shared();

    assert!(shared.length() == 1);

    let gateway_id = shared[0];
    let gateway = scenario.take_shared_by_id<Gateway>(gateway_id);
    let Gateway {
        id,
        inner,
    } = gateway;
    id.delete();

    let (
        operator_result,
        messages,
        signers,
        _,
    ) = inner.destroy<Gateway_v0>().destroy_for_testing();

    assert!(operator == operator_result);
    messages.destroy_empty();

    let (
        epoch,
        mut epoch_by_signers_hash,
        domain_separator_result,
        minimum_rotation_delay_result,
        last_rotation_timestamp,
        previous_signers_retention_result,
    ) = signers.destroy_for_testing();

    let signer_epoch = epoch_by_signers_hash.remove(initial_signers.hash());
    epoch_by_signers_hash.destroy_empty();

    assert!(epoch == 1);
    assert!(signer_epoch == 1);
    assert!(bytes32::new(domain_separator) == domain_separator_result);
    assert!(minimum_rotation_delay == minimum_rotation_delay_result);
    assert!(last_rotation_timestamp == timestamp);
    assert!(previous_signers_retention == previous_signers_retention_result);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure]
fun test_setup_remaining_bytes() {
    let ctx = &mut sui::tx_context::dummy();
    let operator = @123456;
    let domain_separator = @789012;
    let minimum_rotation_delay = 765;
    let previous_signers_retention = 650;
    let initial_signers = axelar_gateway::weighted_signers::dummy();
    let mut clock = sui::clock::create_for_testing(ctx);
    let timestamp = 1234;
    clock.increment_for_testing(timestamp);

    let creator_cap = CreatorCap {
        id: object::new(ctx),
    };

    let mut scenario = sui::test_scenario::begin(@0x1);
    let mut initial_signers_bytes = bcs::to_bytes(&initial_signers);
    initial_signers_bytes.push_back(0);
    setup(
        creator_cap,
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        initial_signers_bytes,
        &clock,
        scenario.ctx(),
    );

    let tx_effects = scenario.next_tx(@0x1);
    let shared = tx_effects.shared();

    assert!(shared.length() == 1);

    let gateway_id = shared[0];
    let gateway = scenario.take_shared_by_id<Gateway>(gateway_id);
    let Gateway {
        id,
        inner,
    } = gateway;
    id.delete();

    let (
        operator_result,
        messages,
        signers,
        _,
    ) = inner.destroy<Gateway_v0>().destroy_for_testing();

    assert!(operator == operator_result);
    messages.destroy_empty();

    let (
        epoch,
        mut epoch_by_signers_hash,
        domain_separator_result,
        minimum_rotation_delay_result,
        last_rotation_timestamp,
        previous_signers_retention_result,
    ) = signers.destroy_for_testing();

    let signer_epoch = epoch_by_signers_hash.remove(initial_signers.hash());
    epoch_by_signers_hash.destroy_empty();

    assert!(epoch == 1);
    assert!(signer_epoch == 1);
    assert!(bytes32::new(domain_separator) == domain_separator_result);
    assert!(minimum_rotation_delay == minimum_rotation_delay_result);
    assert!(last_rotation_timestamp == timestamp);
    assert!(previous_signers_retention == previous_signers_retention_result);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_peel_weighted_signers() {
    let signers = axelar_gateway::weighted_signers::dummy();
    let bytes = bcs::to_bytes(&signers);
    let result = utils::peel!(bytes, |bcs| weighted_signers::peel(bcs));

    assert!(result == signers);
}

#[test]
#[expected_failure]
fun test_peel_weighted_signers_no_remaining_data() {
    let signers = axelar_gateway::weighted_signers::dummy();
    let mut bytes = bcs::to_bytes(&signers);
    bytes.push_back(0);

    utils::peel!(bytes, |bcs| weighted_signers::peel(bcs));
}

#[test]
fun test_peel_proof() {
    let proof = axelar_gateway::proof::dummy();
    let bytes = bcs::to_bytes(&proof);
    let result = utils::peel!(bytes, |bcs| axelar_gateway::proof::peel(bcs));

    assert!(result == proof);
}

#[test]
#[expected_failure]
fun test_peel_proof_no_remaining_data() {
    let proof = axelar_gateway::proof::dummy();
    let mut bytes = bcs::to_bytes(&proof);
    bytes.push_back(0);

    utils::peel!(bytes, |bcs| axelar_gateway::proof::peel(bcs));
}

#[test]
fun test_take_approved_message() {
    let mut gateway = dummy(&mut sui::tx_context::dummy());
    let source_chain = std::ascii::string(b"Source Chain");
    let message_id = std::ascii::string(b"Message Id");
    let source_address = std::ascii::string(b"Source Address");
    let destination_id = @0x1;
    let payload = b"payload";
    let payload_hash = axelar_gateway::bytes32::new(
        sui::address::from_bytes(sui::hash::keccak256(&payload))
    );
    let message = axelar_gateway::message::new(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload_hash,
    );

    gateway.value_mut!(b"")
        .messages_mut()
        .add(
            message.command_id(),
            axelar_gateway::message_status::approved(message.hash()),
        );


    let approved_message = gateway.take_approved_message(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    );
    let expected_approved_message = axelar_gateway::channel::create_approved_message(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload,
    );
    assert!(&approved_message == &expected_approved_message);


    gateway.value_mut!(b"").messages_mut().remove(message.command_id());

    approved_message.destroy_for_testing();
    expected_approved_message.destroy_for_testing();
    gateway.destroy_for_testing();
}

#[test]
fun test_approve_messages() {
    let ctx = &mut sui::tx_context::dummy();
    let keypair = sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x1234.to_bytes());
    let weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *keypair.public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x0),
    );
    let operator = @0x1;
    let domain_separator = bytes32::new(@0x2);
    let minimum_rotation_delay = 1;
    let previous_signers_retention = 10;
    let initial_signers = weighted_signers;
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        initial_signers,
        &clock,
        ctx,
    );
    let messages = vector<axelar_gateway::message::Message>[
        axelar_gateway::message::dummy()
    ];
    let data_hash = gateway_v0::approve_messages_data_hash(messages);
    let proof = generate_proof(data_hash, domain_separator, weighted_signers, &vector[keypair]);

    self.approve_messages(bcs::to_bytes(&messages), bcs::to_bytes(&proof));

    clock.destroy_for_testing();
    sui::test_utils::destroy(self)
}

#[test]
#[expected_failure]
fun test_approve_messages_remaining_data() {
    let ctx = &mut sui::tx_context::dummy();
    let keypair = sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x1234.to_bytes());
    let weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *keypair.public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x0),
    );
    let operator = @0x1;
    let domain_separator = bytes32::new(@0x2);
    let minimum_rotation_delay = 1;
    let previous_signers_retention = 10;
    let initial_signers = weighted_signers;
    let clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        initial_signers,
        &clock,
        ctx,
    );
    let messages = vector[
        axelar_gateway::message::dummy()
    ];
    let data_hash = gateway_v0::approve_messages_data_hash(messages);
    let proof = generate_proof(data_hash, domain_separator, weighted_signers, &vector[keypair]);
    let mut proof_data = bcs::to_bytes(&proof);
    proof_data.push_back(0);

    self.approve_messages(bcs::to_bytes(&messages), proof_data);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self)
}

#[test]
fun test_rotate_signers() {
    let ctx = &mut sui::tx_context::dummy();
    let keypair = sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x1234.to_bytes());
    let weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *keypair.public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x0),
    );
    let next_weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x5678.to_bytes()).public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x1),
    );

    let operator = @0x1;
    let domain_separator = bytes32::new(@0x2);
    let minimum_rotation_delay = 1;
    let previous_signers_retention = 10;
    let initial_signers = weighted_signers;
    let mut clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        initial_signers,
        &clock,
        ctx,
    );

    let data_hash = gateway_v0::rotate_signers_data_hash(next_weighted_signers);
    let proof = generate_proof(data_hash, domain_separator, weighted_signers, &vector[keypair]);

    clock.increment_for_testing(minimum_rotation_delay);
    self.rotate_signers(&clock, bcs::to_bytes(&next_weighted_signers), bcs::to_bytes(&proof), ctx);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure]
fun test_rotate_signers_remaining_data_message_data() {
    let ctx = &mut sui::tx_context::dummy();
    let keypair = sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x1234.to_bytes());
    let weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *keypair.public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x0),
    );
    let next_weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x5678.to_bytes()).public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x1),
    );

    let operator = @0x1;
    let domain_separator = bytes32::new(@0x2);
    let minimum_rotation_delay = 1;
    let previous_signers_retention = 10;
    let initial_signers = weighted_signers;
    let mut clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        initial_signers,
        &clock,
        ctx,
    );

    let mut message_data = bcs::to_bytes(&next_weighted_signers);
    message_data.push_back(0);

    let data_hash = gateway_v0::rotate_signers_data_hash(next_weighted_signers);
    let proof = generate_proof(data_hash, domain_separator, weighted_signers, &vector[keypair]);

    clock.increment_for_testing(minimum_rotation_delay);
    self.rotate_signers(&clock, message_data, bcs::to_bytes(&proof), ctx);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure]
fun test_rotate_signers_remaining_data_proof_data() {
    let ctx = &mut sui::tx_context::dummy();
    let keypair = sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x1234.to_bytes());
    let weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *keypair.public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x0),
    );
    let next_weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x5678.to_bytes()).public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x1),
    );

    let operator = @0x1;
    let domain_separator = bytes32::new(@0x2);
    let minimum_rotation_delay = 1;
    let previous_signers_retention = 10;
    let initial_signers = weighted_signers;
    let mut clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        initial_signers,
        &clock,
        ctx,
    );

    let data_hash = gateway_v0::rotate_signers_data_hash(next_weighted_signers);
    let proof = generate_proof(data_hash, domain_separator, weighted_signers, &vector[keypair]);
    let mut proof_data = bcs::to_bytes(&proof);
    proof_data.push_back(0);

    clock.increment_for_testing(minimum_rotation_delay);
    self.rotate_signers(&clock, bcs::to_bytes(&next_weighted_signers), proof_data, ctx);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self);
}

#[test]
#[expected_failure(abort_code = axelar_gateway::gateway_v0::ENotLatestSigners)]
fun test_rotate_signers_not_latest_signers() {
    let ctx = &mut sui::tx_context::dummy();
    let keypair = sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x1234.to_bytes());
    let weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *keypair.public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x0),
    );
    let next_weighted_signers = weighted_signers::create_for_testing(
        vector[
            axelar_gateway::weighted_signer::new(
                *sui::ecdsa_k1::secp256k1_keypair_from_seed(&@0x5678.to_bytes()).public_key(),
                1,
            )
        ],
        1,
        bytes32::new(@0x2),
    );

    let operator = @0x1;
    let domain_separator = bytes32::new(@0x2);
    let minimum_rotation_delay = 1;
    let previous_signers_retention = 10;
    let initial_signers = weighted_signers;
    let mut clock = sui::clock::create_for_testing(ctx);
    let mut self = create_for_testing(
        operator,
        domain_separator,
        minimum_rotation_delay,
        previous_signers_retention,
        initial_signers,
        &clock,
        ctx,
    );
    // Tell the gateway this is not the latest epoch
    let epoch = self.value_mut!(b"rotate_signers").signers_mut().epoch_mut();
    *epoch = *epoch + 1;

    let data_hash = gateway_v0::rotate_signers_data_hash(next_weighted_signers);
    let proof = generate_proof(data_hash, domain_separator, weighted_signers, &vector[keypair]);

    clock.increment_for_testing(minimum_rotation_delay);
    self.rotate_signers(&clock, bcs::to_bytes(&next_weighted_signers), bcs::to_bytes(&proof), ctx);

    clock.destroy_for_testing();
    sui::test_utils::destroy(self);
}

#[test]
fun test_is_message_approved() {
    let ctx = &mut sui::tx_context::dummy();

    let source_chain = ascii::string(b"Source Chain");
    let source_address = ascii::string(b"Source Address");
    let message_id = ascii::string(b"Message Id");
    let destination_id = @0x4;
    let payload_hash = bytes32::new(@0x5);
    let message = axelar_gateway::message::new(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload_hash,
    );

    let mut gateway = dummy(ctx);
    gateway.value_mut!(b"").approve_message_for_testing(message);
    assert!(gateway.is_message_approved(
        source_chain,
        message_id,
        source_address,
        destination_id,
        payload_hash,
    ));
        assert!(!gateway.is_message_executed(
        source_chain,
        message_id,
    ));

    sui::test_utils::destroy(gateway);
}

#[test]
fun test_send_message() {
    let ctx = &mut sui::tx_context::dummy();
    let channel = axelar_gateway::channel::new(ctx);
    let destination_chain = ascii::string(b"Destination Chain");
    let destination_address = ascii::string(b"Destination Address");
    let payload = b"payload";
    let message_ticket = prepare_message(
        &channel,
        destination_chain,
        destination_address,
        payload,
    );

    let gateway = dummy(ctx);
    gateway.send_message(message_ticket);
    sui::test_utils::destroy(gateway);
    channel.destroy();
}
