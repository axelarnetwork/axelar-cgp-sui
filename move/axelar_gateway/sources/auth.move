module axelar_gateway::auth {
    use sui::bcs;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::Clock;

    use axelar_gateway::weighted_signer::{Self};
    use axelar_gateway::weighted_signers::{WeightedSigners};
    use axelar_gateway::proof::{Proof, Signature};
    use axelar_gateway::bytes32::{Self, Bytes32};

    // ------
    // Errors
    // ------
    const EInvalidWeights: u64 = 0;
    const EInvalidThreshold: u64 = 1;
    /// For when operators have changed, and proof is no longer valid.
    const EInvalidOperators: u64 = 2;
    const EInsufficientRotationDelay: u64 = 3;
    /// For when number of signatures for the call approvals is below the threshold.
    const ELowSignaturesWeight: u64 = 4;
    const EMalformedSigners: u64 = 5;
    const EInvalidEpoch: u64 = 6;

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

    // ------
    // Events
    // ------
    /// Emitted when signers are rotated.
    public struct SignersRotated has copy, drop {
        epoch: u64,
        signers_hash: Bytes32,
        signers: WeightedSigners,
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

        assert!(signers_epoch != 0 && (current_epoch - signers_epoch) <= self.previous_signers_retention, EInvalidEpoch);

        let message = MessageToSign {
            domain_separator: self.domain_separator,
            signers_hash,
            data_hash,
        };

        validate_signatures(
            bcs::to_bytes(&message),
            signers,
            proof.signatures(),
        );

        is_latest_signers
    }

    public(package) fun rotate_signers(self: &mut AxelarSigners, clock: &Clock, new_signers: WeightedSigners, enforce_rotation_delay: bool) {
        validate_signers(&new_signers);

        self.update_rotation_timestamp(clock, enforce_rotation_delay);

        let new_signers_hash = new_signers.hash();
        let epoch = self.epoch + 1;

        // Aborts if the signers already exist
        self.epoch_by_signers_hash.add(new_signers_hash, epoch);
        self.epoch = epoch;

        event::emit(SignersRotated {
            epoch,
            signers_hash: new_signers_hash,
            signers: new_signers,
        })
    }

    // ------------------
    // Internal Functions
    // ------------------

    fun validate_signatures(
        message: vector<u8>,
        signers: &WeightedSigners,
        signatures: &vector<Signature>,
    ) {
        let signers_length = signers.signers().length();
        let signatures_length = signatures.length();
        assert!(signatures_length != 0, ELowSignaturesWeight);

        let threshold = signers.threshold();
        let mut signer_index = 0;
        let mut total_weight = 0;
        let mut i = 0;

        while (i < signatures_length) {
            let pub_key = signatures[i].recover_pub_key(&message);

            while (signer_index < signers_length && signers.signers()[signer_index].pub_key() != pub_key) {
                signer_index = signer_index + 1;
            };

            assert!(signer_index < signers_length, EMalformedSigners);

            total_weight = total_weight + signers.signers()[signer_index].weight();

            if (total_weight >= threshold) {
                return
            };

            signer_index = signer_index + 1;
            i = i + 1;
        };

        abort ELowSignaturesWeight
    }

    fun validate_signers(signers: &WeightedSigners) {
        let signers_length = signers.signers().length();
        assert!(signers_length != 0, EInvalidOperators);

        let mut total_weight = 0;
        let mut i = 0;
        let mut previous_signer = weighted_signer::default();

        while (i < signers_length) {
            let current_signer = signers.signers()[i];
            assert!(previous_signer.lt(&current_signer), EInvalidOperators);

            let weight = current_signer.weight();
            assert!(weight != 0, EInvalidWeights);

            total_weight = total_weight + weight;
            i = i + 1;
            previous_signer = current_signer;
        };

        let threshold = signers.threshold();
        assert!(threshold != 0 && total_weight >= threshold, EInvalidThreshold);
    }

    fun update_rotation_timestamp(self: &mut AxelarSigners, clock: &Clock, enforce_rotation_delay: bool) {
        let current_timestamp = clock.timestamp_ms();

        // If the rotation delay is enforced, the current timestamp should be greater than the last rotation timestamp plus the minimum rotation delay.
        assert!(!enforce_rotation_delay || current_timestamp >= self.last_rotation_timestamp + self.minimum_rotation_delay, EInsufficientRotationDelay);

        self.last_rotation_timestamp = current_timestamp;
    }

    #[test_only]
    public fun dummy_for_testing(ctx: &mut TxContext): AxelarSigners {
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
    public fun destroy_for_testing(signers: AxelarSigners): (
        u64,
        Table<Bytes32, u64>,
        Bytes32,
        u64,
        u64,
        u64,
    ) {
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
}
