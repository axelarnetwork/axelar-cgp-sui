// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module axelar_gateway::auth {
    use sui::bcs;
    use sui::ecdsa_k1 as ecdsa;
    use sui::event;
    use sui::vec_map:: {Self, VecMap};

    use axelar_gateway::utils::{normalize_signature, operators_hash, is_address_vector_zero, compare_address_vectors};
    use axelar_gateway::weighted_signers::{Self};

    const EInvalidWeights: u64 = 0;
    const EInvalidThreshold: u64 = 1;
    /// For when operators have changed, and proof is no longer valid.
    const EInvalidOperators: u64 = 2;
    // const EDuplicateOperators: u64 = 3;
    /// For when number of signatures for the call approvals is below the threshold.
    const ELowSignaturesWeight: u64 = 4;
    const EMalformedSigners: u64 = 5;

    /// Used for a check in `validate_proof` function.
    const OLD_KEY_RETENTION: u64 = 16;

    public struct AxelarValidators has store {
        /// Epoch of the validators.
        epoch: u64,
        /// Epoch for the signers hash.
        epoch_by_signers_hash: VecMap<vector<u8>, u64>,
    }

    /// Emitted when the operatorship changes.
    public struct OperatorshipTransferred has copy, drop {
        epoch: u64,
        payload: vector<u8>,
    }

    public(package) fun new(): AxelarValidators {
        AxelarValidators {
            epoch: 0,
            epoch_by_signers_hash: vec_map::empty(),
        }
    }

    /// Implementation of the `AxelarAuthWeighted.validateProof`.
    /// Does proof validation, fails when proof is invalid or if weight
    /// threshold is not reached.
    public(package) fun validate_proof(
        validators: &AxelarValidators,
        approval_hash: vector<u8>,
        proof: vector<u8>
    ): bool {
        let epoch = epoch(validators);
        // Allow the validators to validate any proof before the first set of operators is set (so that they can be rotated).
        if (epoch == 0) {
            return true
        };

        // Turn everything into bcs bytes and split data.
        let mut proof = bcs::new(proof);

        let (operators, weights, threshold, signatures) = (
            proof.peel_vec_vec_u8(),
            proof.peel_vec_u128(),
            proof.peel_u128(),
            proof.peel_vec_vec_u8()
        );

        let operators_length = vector::length(&operators);
        let operators_epoch = *epoch_by_signers_hash(validators)
            .get(&operators_hash(&operators, &weights, threshold));

        // This error cannot be hit because we remove old operators and no set has an epoch of 0.
        assert!(operators_epoch != 0 && epoch - operators_epoch < OLD_KEY_RETENTION, EInvalidOperators);
        let (mut i, mut weight, mut operator_index) = (0, 0, 0);
        let total_signatures = vector::length(&signatures);
        while (i < total_signatures) {

            let mut signature = *vector::borrow(&signatures, i);
            normalize_signature(&mut signature);

            let signed_by: vector<u8> = ecdsa::secp256k1_ecrecover(&signature, &approval_hash, 0);
            while (operator_index < operators_length && &signed_by != vector::borrow(&operators, operator_index)) {
                operator_index = operator_index + 1;
            };

            assert!(operator_index < operators_length, EMalformedSigners);

            weight = weight + *vector::borrow(&weights, operator_index);
            if (weight >= threshold) { return operators_epoch == epoch };
            operator_index = operator_index + 1;

            i = i + 1;
        };

        abort ELowSignaturesWeight
    }

    public(package) fun transfer_operatorship(validators: &mut AxelarValidators, payload: vector<u8>) {
        let mut bcs = bcs::new(payload);
        let new_operators = bcs.peel_vec_vec_u8();
        let new_weights = bcs.peel_vec_u128();
        let new_threshold = bcs.peel_u128();

        let operators_length = vector::length(&new_operators);
        let weight_length = vector::length(&new_weights);

        assert!(operators_length != 0 && is_sorted_asc_and_contains_no_duplicate(&new_operators), EInvalidOperators);

        assert!(weight_length == operators_length, EInvalidWeights);
        let (mut total_weight, mut i) = (0, 0);
        while (i < weight_length) {
            total_weight = total_weight + *vector::borrow(&new_weights, i);
            i = i + 1;
        };
        assert!(!(new_threshold == 0 || total_weight < new_threshold), EInvalidThreshold);

        let new_operators_hash = operators_hash(&new_operators, &new_weights, new_threshold);
        // Remove old epoch for the operators if it exists
        let epoch = validators.epoch() + 1;
        let epoch_by_signers_hash = validators.epoch_by_signers_hash_mut();
        if (epoch_by_signers_hash.contains(&new_operators_hash)) {
            epoch_by_signers_hash.remove(&new_operators_hash);
        };

        // clean up old epoch
        if (epoch >= OLD_KEY_RETENTION && epoch_by_signers_hash.size() > 0) {
            let old_epoch = epoch - OLD_KEY_RETENTION;
            let (_, epoch) = epoch_by_signers_hash.get_entry_by_idx(0);
            if (*epoch <= old_epoch) {
                epoch_by_signers_hash.remove_entry_by_idx(0);
            };
        };
        epoch_by_signers_hash.insert(new_operators_hash, epoch);

        set_epoch(validators, epoch);

        event::emit(OperatorshipTransferred {
            epoch,
            payload
        });
    }

    public(package) fun rotate_signers(validators: &mut AxelarValidators, new_signers: weighted_signers::WeightedSigners) {
        transfer_operatorship(validators, bcs::to_bytes(&new_signers))
    }

    // === Getters ===

    fun epoch_by_signers_hash(validators: &AxelarValidators): &VecMap<vector<u8>, u64> {
        &validators.epoch_by_signers_hash
    }

    fun epoch_by_signers_hash_mut(validators: &mut AxelarValidators): &mut VecMap<vector<u8>, u64> {
        &mut validators.epoch_by_signers_hash
    }

    fun set_epoch(validators: &mut AxelarValidators, epoch: u64) {
        validators.epoch = epoch
    }

    public fun epoch(validators: &AxelarValidators): u64 {
        validators.epoch
    }

    fun is_sorted_asc_and_contains_no_duplicate(accounts: &vector<vector<u8>>): bool {
        let accountsLength = vector::length(accounts);
        let mut prevAccount = vector::borrow(accounts, 0);

        if (is_address_vector_zero(prevAccount)) {
            return false
        };

        let mut i = 1;
        while (i < accountsLength) {
            let currAccount = vector::borrow(accounts, i);

            if (!compare_address_vectors(prevAccount, currAccount)) {
                return false
            };

            prevAccount = currAccount;
            i = i + 1;
        };

        true
    }

    // === Testing ===

    #[test_only]
    use axelar_gateway::utils::to_sui_signed;

    #[test_only]
    /// Signer PubKey.
    /// Expected to be returned from ecrecover.
    const SIGNER: vector<u8> = x"037286a4f1177bea06c8e15cf6ec3df0b7747a01ac2329ca2999dfd74eff599028";

    #[test_only]
    public fun get_transfer_params(new_operators: &vector<vector<u8>>, new_weights: &vector<u128>, new_threshold: &u128): vector<u8> {
        let mut bcs = vector::empty<u8>();
        vector::append(&mut bcs, bcs::to_bytes(new_operators));
        vector::append(&mut bcs, bcs::to_bytes(new_weights));
        vector::append(&mut bcs, bcs::to_bytes(new_threshold));
        bcs
    }

    #[test_only]
    public fun test_contains_operators(self: &AxelarValidators, operators: &vector<vector<u8>>, weights: &vector<u128>, threshold: u128): bool {
        self.epoch_by_signers_hash.contains(
            &operators_hash(
                operators,
                weights,
                threshold,
            )
        )
    }


    #[test_only]
    public fun test_epoch_for_operators(self: &AxelarValidators, operators: &vector<vector<u8>>, weights: &vector<u128>, threshold: u128): u64 {
        *self.epoch_by_signers_hash.get(
            &operators_hash(
                operators,
                weights,
                threshold,
            )
        )
    }

    #[test]
    /// Tests `ecrecover`, makes sure external signing process works with Sui ecrecover.
    /// Samples for this test are generated with the `presets/` application.
    fun test_ecrecover() {
        let message = x"68656c6c6f20776f726c64"; // hello world
        let mut signature = x"0e88ac153a06d86f28dc0f946654d02302099c0c6558806b569d43f8bd062d5c295beb095e9cc396cd68a6b18daa0f1c0489b778831c4b3bb46f7aa1171c23b101";

        normalize_signature(&mut signature);
        let pubkey = ecdsa::secp256k1_ecrecover(&signature, &to_sui_signed(message), 0);

        assert!(pubkey == SIGNER, 0);
    }

    #[test]
    /// Tests "Sui Signed Message" prefix addition ecrecover.
    /// Checks if the signature generated outside matches the message generated in this module.
    /// Samples for this test are generated with the `presets/` application.
    fun test_to_signed() {
        let message = b"hello world";
        let mut signature = x"0e88ac153a06d86f28dc0f946654d02302099c0c6558806b569d43f8bd062d5c295beb095e9cc396cd68a6b18daa0f1c0489b778831c4b3bb46f7aa1171c23b101";
        normalize_signature(&mut signature);

        let pub_key = ecdsa::secp256k1_ecrecover(&signature, &to_sui_signed(message), 0);
        assert!(pub_key == SIGNER, 0);
    }

    #[test]
    fun test_transfer_operatorship() {
        let mut validators = new();

        let operators = vector[x"0123", x"4567", x"890a"];
        let weights = vector[1, 3, 6];
        let threshold = 4;
        let payload = x"0302012302456702890a0301000000000000000000000000000000030000000000000000000000000000000600000000000000000000000000000004000000000000000000000000000000";

        validators.transfer_operatorship(payload);

        let epoch = validators.epoch_by_signers_hash.get(&operators_hash(&operators, &weights, threshold));

        assert!(*epoch == 1, 0);

        sui::test_utils::destroy(validators);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidOperators)]
    fun test_transfer_operatorship_zero_operator_length() {
        let mut validators = new();

        let payload = x"000301000000000000000000000000000000030000000000000000000000000000000600000000000000000000000000000004000000000000000000000000000000";

        validators.transfer_operatorship(payload);

        sui::test_utils::destroy(validators);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidOperators)]
    fun test_transfer_operatorship_unsorted_operatros() {
        let mut validators = new();

        let payload = x"0302456702012302890a0301000000000000000000000000000000030000000000000000000000000000000600000000000000000000000000000004000000000000000000000000000000";

        validators.transfer_operatorship(payload);

        sui::test_utils::destroy(validators);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidOperators)]
    fun test_transfer_operatorship_duplicate_operatros() {
        let mut validators = new();

        let payload = x"0302012302890a02890a0301000000000000000000000000000000030000000000000000000000000000000600000000000000000000000000000004000000000000000000000000000000";

        validators.transfer_operatorship(payload);

        sui::test_utils::destroy(validators);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidWeights)]
    fun test_transfer_operatorship_invalid_weights() {
        let mut validators = new();

        let payload = x"0302012302456702890a02010000000000000000000000000000000300000000000000000000000000000004000000000000000000000000000000";

        validators.transfer_operatorship(payload);

        sui::test_utils::destroy(validators);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidThreshold)]
    fun test_transfer_operatorship_zero_threshold() {
        let mut validators = new();

        let payload = x"0302012302456702890a0301000000000000000000000000000000030000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000";

        validators.transfer_operatorship(payload);

        sui::test_utils::destroy(validators);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidThreshold)]
    fun test_transfer_operatorship_threshold_too_high() {
        let mut validators = new();

        let payload = x"0302012302456702890a030100000000000000000000000000000003000000000000000000000000000000060000000000000000000000000000000b000000000000000000000000000000";

        validators.transfer_operatorship(payload);

        sui::test_utils::destroy(validators);
    }

    #[test]
    fun test_validate_proof() {
        let mut validators = new();

        let message = x"123456";
        let payload = x"032102dd7312374396c51c50f95e0c1f370435292de4809b755aca09b49fcd8d0fe9c02103595d141e66c2c1e8e0c114b71ddc9db53a65743e7679a02a4c8c71af16d4522821039494a3cde8ae663d21a0b8692549c56887901c7e4529b0fdb6ce3d39b382bea10303000000000000000000000000000000030000000000000000000000000000000300000000000000000000000000000006000000000000000000000000000000";
        let proof = x"032102dd7312374396c51c50f95e0c1f370435292de4809b755aca09b49fcd8d0fe9c02103595d141e66c2c1e8e0c114b71ddc9db53a65743e7679a02a4c8c71af16d4522821039494a3cde8ae663d21a0b8692549c56887901c7e4529b0fdb6ce3d39b382bea1030300000000000000000000000000000003000000000000000000000000000000030000000000000000000000000000000600000000000000000000000000000003413de59beca835483688338964eb4c314f387e06aef6c46ca2dc90733e5b7baa9b67b9b8530aacaae4263e369fced014e449166441c21b61fcef5978516d1a740301417b6940537f7fa65d37d0964d5dda49b80b5b7fcde93ba3b3224c3e007ff887ee20a203ac52802c29238353b69636cb71bd1da3bdb0c3ac3d85938531f94dd7570041529af0061fa6321419e0b702dd1ac4e16610efa718ad241e4eda8b65dd92bd2e715cfd58951305f6fc4d75a20d2c19bd4491312cff38b9694b02e2175826a2c800";
        let payload2 = x"032102dd7312374396c51c50f95e0c1f370435292de4809b755aca09b49fcd8d0fe9c02103595d141e66c2c1e8e0c114b71ddc9db53a65743e7679a02a4c8c71af16d4522821039494a3cde8ae663d21a0b8692549c56887901c7e4529b0fdb6ce3d39b382bea10303000000000000000000000000000000030000000000000000000000000000000300000000000000000000000000000007000000000000000000000000000000";

        validators.transfer_operatorship(payload);
        assert!(validators.validate_proof(to_sui_signed(message), proof) == true, 0);

        validators.transfer_operatorship(payload2);
        assert!(validators.validate_proof(to_sui_signed(message), proof) == false, 0);

        sui::test_utils::destroy(validators);
    }

    #[test]
    #[expected_failure(abort_code = EMalformedSigners)]
    fun test_validate_proof_malformed_signers() {
        let mut validators = new();

        let message = x"1234";
        let payload = x"032102dd7312374396c51c50f95e0c1f370435292de4809b755aca09b49fcd8d0fe9c02103595d141e66c2c1e8e0c114b71ddc9db53a65743e7679a02a4c8c71af16d4522821039494a3cde8ae663d21a0b8692549c56887901c7e4529b0fdb6ce3d39b382bea10303000000000000000000000000000000030000000000000000000000000000000300000000000000000000000000000006000000000000000000000000000000";
        let proof = x"032102dd7312374396c51c50f95e0c1f370435292de4809b755aca09b49fcd8d0fe9c02103595d141e66c2c1e8e0c114b71ddc9db53a65743e7679a02a4c8c71af16d4522821039494a3cde8ae663d21a0b8692549c56887901c7e4529b0fdb6ce3d39b382bea1030300000000000000000000000000000003000000000000000000000000000000030000000000000000000000000000000600000000000000000000000000000003413de59beca835483688338964eb4c314f387e06aef6c46ca2dc90733e5b7baa9b67b9b8530aacaae4263e369fced014e449166441c21b61fcef5978516d1a740301417b6940537f7fa65d37d0964d5dda49b80b5b7fcde93ba3b3224c3e007ff887ee20a203ac52802c29238353b69636cb71bd1da3bdb0c3ac3d85938531f94dd7570041529af0061fa6321419e0b702dd1ac4e16610efa718ad241e4eda8b65dd92bd2e715cfd58951305f6fc4d75a20d2c19bd4491312cff38b9694b02e2175826a2c800";

        validators.transfer_operatorship(payload);
        validators.validate_proof(to_sui_signed(message), proof);

        sui::test_utils::destroy(validators);
    }
}
