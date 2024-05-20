module axelar_gateway::bytes32 {
    use sui::bcs::BCS;

    /// -----
    /// Types
    /// -----
    public struct Bytes32 has copy, drop, store {
        bytes: vector<u8>,
    }

    /// ---------
    /// Constants
    /// ---------
    const LEN: u64 = 32;

    /// ------
    /// Errors
    /// ------
    /// Invalid length for bytes32 cast
    const EInvalidLength: u64 = 0;

    /// ----------------
    /// Public Functions
    /// ----------------
    /// Casts a vector of bytes to a bytes32
    public fun new(bytes: vector<u8>): Bytes32 {
        assert!(bytes.length() == LEN, EInvalidLength);

        Bytes32{bytes: bytes}
    }

    public fun default(): Bytes32 {
        let mut bytes: vector<u8> = vector[];
        let mut i: u64 = 0;

        while (i < LEN) {
            vector::push_back(&mut bytes, 0);
            i = i + 1;
        };

        Bytes32{bytes: bytes}
    }

    public fun from_bytes(bytes: vector<u8>): Bytes32 {
        new(bytes)
    }

    public fun to_bytes(self: Bytes32): vector<u8> {
        self.bytes
    }

    public fun validate(self: &Bytes32) {
        assert!(self.bytes.length() == 32, EInvalidLength);
    }

    public fun length(_self: &Bytes32): u64 {
        LEN
    }

    public(package) fun peel(bcs: &mut BCS): Bytes32 {
        let bytes = bcs.peel_vec_u8();
        new(bytes)
    }
}

#[test_only]
module axelar_gateway::bytes32_tests {
    use axelar_gateway::bytes32::{Self};

    #[test]
    public fun new() {
        let bytes =
            x"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
        let actual = bytes32::new(bytes);

        assert!(actual.to_bytes() == bytes, 0);
    }
}
