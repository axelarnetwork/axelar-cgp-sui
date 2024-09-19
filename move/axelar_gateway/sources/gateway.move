/// Implementation of the Axelar Gateway for Sui Move.
///
/// This code is based on the following:
///
/// - When call approvals is sent to Sui, it targets an object and not a module;
/// - To support cross-chain messaging, a Channel object has to be created;
/// - Channel can be either owned or shared but not frozen;
/// - Module developer on the Sui side will have to implement a system to support messaging;
/// - Checks for uniqueness of approvals should be done through `Channel`s to avoid big data storage;
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
/// The Gateway object uses a versioned field to support upgradability. The current implementation uses GatewayV0.
module axelar_gateway::gateway;

use axelar_gateway::auth::{Self, validate_proof};
use axelar_gateway::bytes32::Bytes32;
use axelar_gateway::channel::{Channel, ApprovedMessage};
use axelar_gateway::weighted_signers;
use axelar_gateway::message_ticket::{Self, MessageTicket};
use axelar_gateway::gateway_v0::{Self, GatewayV0};
use std::ascii::String;
use sui::address;
use sui::clock::Clock;
use sui::hash;
use sui::table::{Self};
use sui::versioned::{Self, Versioned};
use version_control::version_control::{Self, VersionControl};
use utils::utils;

// -------
// Version
// -------
const VERSION: u64 = 0;

// ------
// Errors
// ------
/// MessageTickets created from newer versions cannot be sent here
const ENewerMessage: u64 = 0;

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

// ------
// Events
// ------
/// Emitted when a new message is sent from the SUI network.
public struct ContractCall has copy, drop {
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    payload_hash: address,
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
public fun setup(
    cap: CreatorCap,
    operator: address,
    domain_separator: Bytes32,
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
                domain_separator,
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
macro fun value($self: &Gateway): &GatewayV0 {
    let gateway = $self;
    gateway.inner.load_value<GatewayV0>()
}

macro fun fields_mut($self: &mut Gateway): &mut GatewayV0 {
    let gateway = $self;
    gateway.inner.load_value_mut<GatewayV0>()
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
    let data = self.fields_mut!();
    data.version_control().check(VERSION, b"approve_messages");
    data.approve_messages(message_data, proof_data);
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
    let data = self.fields_mut!();
    data.version_control().check(VERSION, b"rotate_signers");
    data.rotate_signers(
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
    message: MessageTicket,
) {
    let (
        source_id,
        destination_chain,
        destination_address,
        payload,
        version,
    ) = message.destroy();
    assert!(version <= VERSION, ENewerMessage);
    sui::event::emit(ContractCall {
        source_id,
        destination_chain,
        destination_address,
        payload,
        payload_hash: address::from_bytes(hash::keccak256(&payload)),
    });
}

public fun is_message_approved(
    self: &Gateway,
    source_chain: String,
    message_id: String,
    source_address: String,
    destination_id: address,
    payload_hash: Bytes32,
): bool {
    let data = self.value!();
    data.version_control().check(VERSION, b"is_message_approved");
    data.is_message_approved(
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
    let data = self.value!();
    data.version_control().check(VERSION, b"is_message_executed");
    data.is_message_executed(source_chain, message_id)
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
    let data = self.fields_mut!();
    data.version_control().check(VERSION, b"take_approved_message");
    data.take_approved_message(
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
            ]
        ]
    )
}

#[test_only]
use sui::bcs;

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
public fun dummy(ctx: &mut TxContext): Gateway {
    let inner = versioned::create(
        VERSION,
        gateway_v0::new(
            @0x0,
            table::new(ctx),
            auth::dummy(ctx),
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
public fun destroy_for_testing(self: Gateway) {
    let Gateway {
        id, 
        inner,
    } = self;
    id.delete();

    let data = inner.destroy<GatewayV0>();
    let (
        _,
        messages,
        signers,
        _,
    ) = data.destroy_for_testing();

    let (_, table, _, _, _, _) = signers.destroy_for_testing();
    table.destroy_empty();
    messages.destroy_empty();
}

#[test]
fun test_setup() {
    let ctx = &mut sui::tx_context::dummy();
    let operator = @123456;
    let domain_separator = axelar_gateway::bytes32::new(@789012);
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

    assert!(shared.length() == 1, 0);

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
    ) = inner.destroy<GatewayV0>().destroy_for_testing();

    assert!(operator == operator_result, 1);
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

    assert!(epoch == 1, 2);
    assert!(signer_epoch == 1, 3);
    assert!(domain_separator == domain_separator_result, 4);
    assert!(minimum_rotation_delay == minimum_rotation_delay_result, 5);
    assert!(last_rotation_timestamp == timestamp, 6);
    assert!(previous_signers_retention == previous_signers_retention_result, 7);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_peel_weighted_signers() {
    let signers = axelar_gateway::weighted_signers::dummy();
    let bytes = bcs::to_bytes(&signers);
    let result = utils::peel!(bytes, |bcs| weighted_signers::peel(bcs));

    assert!(result == signers, 0);
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

    assert!(result == proof, 0);
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
#[expected_failure(abort_code = axelar_gateway::gateway_v0::EMessageNotApproved)]
fun test_take_approved_message_message_not_approved() {
    let mut gateway = dummy(&mut sui::tx_context::dummy());

    let message = axelar_gateway::message::new(
        std::ascii::string(b"Source Chain"),
        std::ascii::string(b"Message Id"),
        std::ascii::string(b"Source Address"),
        @0x1,
        axelar_gateway::bytes32::new(@0x2),
    );

    fields_mut!(&mut gateway)
        .messages_mut()
        .add(
            message.command_id(),
            axelar_gateway::message_status::approved(axelar_gateway::bytes32::new(@0x3)),
        );

    let approved_message = take_approved_message(
        &mut gateway,
        std::ascii::string(b"Source Chain"),
        std::ascii::string(b"Message Id"),
        std::ascii::string(b"Source Address"),
        @0x12,
        vector[0, 1, 2],
    );

    fields_mut!(&mut gateway).messages_mut().remove(message.command_id());

    approved_message.destroy_for_testing();
    destroy_for_testing(gateway);
}
