// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module axelar::utils {
    use std::vector;

    use sui::bcs;
    use sui::hash;

    const EInvalidSignatureLength: u64 = 0;
    const EVectorLengthMismatch: u64 = 1;

    /// Prefix for Sui Messages.
    const PREFIX: vector<u8> = b"\x19Sui Signed Message:\n";

    /// Normalize last byte of the signature. Have it 1 or 0.
    /// See https://tech.mystenlabs.com/cryptography-in-sui-cross-chain-signature-verification/
    public fun normalize_signature(signature: &mut vector<u8>) {
        // Compute v = 0 or 1.
        assert!(vector::length<u8>(signature) == 65, EInvalidSignatureLength);
        let v = vector::borrow_mut(signature, 64);
        if (*v == 27) {
            *v = 0;
        } else if (*v == 28) {
            *v = 1;
        } else if (*v > 35) {
            *v = (*v - 1) % 2;
        };
    }

    /// Add a prefix to the bytes.
    public fun to_sui_signed(bytes: vector<u8>): vector<u8> {
        let mut res = vector[];
        vector::append(&mut res, PREFIX);
        vector::append(&mut res, bytes);
        res
    }

    /// Compute operators hash from the list of `operators` (public keys).
    /// This hash is used in `Axelar.epoch_for_hash`.
    public fun operators_hash(operators: &vector<vector<u8>>, weights: &vector<u128>, threshold: u128): vector<u8> {
        let mut data = bcs::to_bytes(operators);
        vector::append(&mut data, bcs::to_bytes(weights));
        vector::append(&mut data, bcs::to_bytes(&threshold));
        hash::keccak256(&data)
    }

    public fun is_address_vector_zero(v: &vector<u8>): bool {
        let length = vector::length(v);
        let mut i = 0;
        while(i < length) {
            if(*vector::borrow(v, i) != 0) return false;
            i = i + 1;
        };
        true
    }

    public fun compare_address_vectors(v1: &vector<u8>, v2: &vector<u8>): bool {
        let length = vector::length(v1);
        assert!(length == vector::length(v2), EVectorLengthMismatch); 
        let mut i = 0;
        while(i < length) {
            let b1 = *vector::borrow(v1, i);
            let b2 = *vector::borrow(v2, i);
            if(b1 < b2) {
                return true
            } else if(b1 > b2) {
                return false
            };
            i = i + 1;
        };
        false
    }

    #[test]
    #[expected_failure(abort_code = EInvalidSignatureLength)]
    fun test_normalize_signature() {
        let prefix = x"5f7809eb09754577387a816582ece609511d0262b2c52aa15306083ca3c85962066d6f64756c650866756e6374696f6e02021234025678020574797065310574";
        let mut signature = x"5f7809eb09754577387a816582ece609511d0262b2c52aa15306083ca3c85962066d6f64756c650866756e6374696f6e02021234025678020574797065310574";
        let inputs = vector[0, 1, 10, 11, 27, 28, 30, 38, 39];
        let outputs = vector[0, 1, 10, 11, 0, 1, 30, 1, 0]; 

        let length = vector::length(&inputs);
        let mut i = 0;
        while(i < length) {
            vector::push_back(&mut signature, *vector::borrow(&inputs, i));
            normalize_signature(&mut signature);
            assert!(vector::pop_back(&mut signature) == *vector::borrow(&outputs, i), i);
            assert!(signature == prefix, i);
            i = i + 1;
        };

        normalize_signature(&mut signature);
    }

    #[test]
    fun test_to_sui_signed() {
        let input = b"012345";
        let output = b"\x19Sui Signed Message:\n012345";
        assert!(to_sui_signed(input) == output, 0);
    }

    #[test]
    fun test_operators_hash() {
        let operators = vector[x"0123", x"4567", x"890a"];
        let weights = vector[1, 3, 6];
        let threshold = 4;
        let output = x"dd5d3f9c1017e8356ea1858db7b89800b6cd43775c5c1b7c633f6ef933583cfd";
        
        assert!(operators_hash(&operators, &weights, threshold) == output, 0);
    }

    #[test]
    fun test_is_address_vector_zero() {
        assert!(is_address_vector_zero(&x"01") == false, 0);
        assert!(is_address_vector_zero(&x"") == true, 0);
        assert!(is_address_vector_zero(&x"00") == true, 0);
        assert!(is_address_vector_zero(&x"00000000000001") == false, 0);
        assert!(is_address_vector_zero(&x"00000000000000") == true, 0);
    }

    #[test]
    #[expected_failure(abort_code = EVectorLengthMismatch)]
    fun test_compare_address_vectors() {
        let v1 = &x"000000";
        let v2 = &x"000001";
        let v2copy = &x"000001";
        let v3 = &x"010000";

        assert!(compare_address_vectors(v1, v2) == true, 0);
        assert!(compare_address_vectors(v1, v3) == true, 1);
        assert!(compare_address_vectors(v2, v3) == true, 2);

        assert!(compare_address_vectors(v2, v1) == false, 3);
        assert!(compare_address_vectors(v3, v2) == false, 4);
        assert!(compare_address_vectors(v3, v1) == false, 5);

        assert!(compare_address_vectors(v2, v2copy) == false, 6);

        compare_address_vectors(&x"", &x"01");
    }
}
