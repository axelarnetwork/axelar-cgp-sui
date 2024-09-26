module axelar_gateway::auth;

use sui::bcs;
use sui::clock::Clock;
use sui::table::{Self, Table};

use axelar_gateway::bytes32::{Self, Bytes32};
use axelar_gateway::proof::{Proof};
use axelar_gateway::weighted_signers::WeightedSigners;
use axelar_gateway::events;

// ------
// Errors
// ------
#[error]
const EInsufficientRotationDelay: vector<u8> = b"insufficient rotation delay";

#[error]
const EInvalidEpoch: vector<u8> = b"the difference between current_epoch and signers_epoch exceeds the allowed retention period";

// -----
// Types
// -----
public struct AxelarSigners has store {
    /// Epoch of the signers.
    epoch: u64,
    /// Epoch for the signers hash.
    epoch_by_signers_hash: Table<Bytes32, u64>,
    /// Domain separator between chains.
    domain_separator: Bytes32,
    /// Minimum rotation delay.
    minimum_rotation_delay: u64,
    /// Timestamp of the last rotation.
    last_rotation_timestamp: u64,
    /// Number of previous signers retained (latest signer isn't included in the count).
    previous_signers_retention: u64,
}

public struct MessageToSign has copy, drop, store {
    domain_separator: Bytes32,
    signers_hash: Bytes32,
    data_hash: Bytes32,
}

// -----------------
// Package Functions
// -----------------
public(package) fun new(ctx: &mut TxContext): AxelarSigners {
    AxelarSigners {
        epoch: 0,
        epoch_by_signers_hash: table::new(ctx),
        domain_separator: bytes32::default(),
        minimum_rotation_delay: 0,
        last_rotation_timestamp: 0,
        previous_signers_retention: 0,
    }
}

public(package) fun setup(
    domain_separator: Bytes32,
    minimum_rotation_delay: u64,
    previous_signers_retention: u64,
    initial_signers: WeightedSigners,
    clock: &Clock,
    ctx: &mut TxContext,
): AxelarSigners {
    let mut signers = AxelarSigners {
        epoch: 0,
        epoch_by_signers_hash: table::new(ctx),
        domain_separator,
        minimum_rotation_delay,
        last_rotation_timestamp: 0,
        previous_signers_retention,
    };

    signers.rotate_signers(clock, initial_signers, false);

    signers
}

public(package) fun validate_proof(
    self: &AxelarSigners,
    data_hash: Bytes32,
    proof: Proof,
): bool {
    let signers = proof.signers();
    let signers_hash = signers.hash();
    let signers_epoch = self.epoch_by_signers_hash[signers_hash];
    let current_epoch = self.epoch;
    let is_latest_signers = current_epoch == signers_epoch;

    assert!(
        signers_epoch != 0 &&
        (current_epoch - signers_epoch) <= self.previous_signers_retention,
        EInvalidEpoch,
    );

    proof.validate(bcs::to_bytes(&MessageToSign {
        domain_separator: self.domain_separator,
        signers_hash,
        data_hash,
    }));

    is_latest_signers
}

public(package) fun rotate_signers(
    self: &mut AxelarSigners,
    clock: &Clock,
    new_signers: WeightedSigners,
    enforce_rotation_delay: bool,
) {
    new_signers.validate();

    self.update_rotation_timestamp(clock, enforce_rotation_delay);

    let new_signers_hash = new_signers.hash();
    let epoch = self.epoch + 1;

    // Aborts if the signers already exist
    self.epoch_by_signers_hash.add(new_signers_hash, epoch);
    self.epoch = epoch;

    events::signers_rotated(
        epoch,
        new_signers_hash,
        new_signers,
    );
}

// ------------------
// Internal Functions
// ------------------

fun update_rotation_timestamp(
    self: &mut AxelarSigners,
    clock: &Clock,
    enforce_rotation_delay: bool,
) {
    let current_timestamp = clock.timestamp_ms();

    // If the rotation delay is enforced, the current timestamp should be greater than the last rotation timestamp plus the minimum rotation delay.
    assert!(
        !enforce_rotation_delay ||
        current_timestamp >=
        self.last_rotation_timestamp + self.minimum_rotation_delay,
        EInsufficientRotationDelay,
    );

    self.last_rotation_timestamp = current_timestamp;
}

#[test_only]
public fun dummy(ctx: &mut TxContext): AxelarSigners {
    AxelarSigners {
        epoch: 0,
        epoch_by_signers_hash: table::new(ctx),
        domain_separator: bytes32::new(@0x1),
        minimum_rotation_delay: 1,
        last_rotation_timestamp: 0,
        previous_signers_retention: 3,
    }
}

#[test_only]
public fun destroy_for_testing(
    signers: AxelarSigners,
): (u64, Table<Bytes32, u64>, Bytes32, u64, u64, u64) {
    let AxelarSigners {
        epoch,
        epoch_by_signers_hash,
        domain_separator,
        minimum_rotation_delay,
        last_rotation_timestamp,
        previous_signers_retention,
    } = signers;
    (
        epoch,
        epoch_by_signers_hash,
        domain_separator,
        minimum_rotation_delay,
        last_rotation_timestamp,
        previous_signers_retention,
    )
}
