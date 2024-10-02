module axelar_gateway::bytes32;

use sui::address;
use sui::bcs::BCS;

// -----
// Types
// -----

public struct Bytes32 has copy, drop, store {
    bytes: address,
}

// ---------
// Constants
// ---------

const LENGTH: u64 = 32;

// ----------------
// Public Functions
// ----------------

/// Casts an address to a bytes32
public fun new(bytes: address): Bytes32 {
    Bytes32 { bytes: bytes }
}

public fun default(): Bytes32 {
    Bytes32 { bytes: @0x0 }
}

public fun from_bytes(bytes: vector<u8>): Bytes32 {
    new(address::from_bytes(bytes))
}

public fun from_address(addr: address): Bytes32 {
    new(addr)
}

public fun to_bytes(self: Bytes32): vector<u8> {
    self.bytes.to_bytes()
}

public fun length(_self: &Bytes32): u64 {
    LENGTH
}

public(package) fun peel(bcs: &mut BCS): Bytes32 {
    new(bcs.peel_address())
}

// -----
// Tests
// -----

#[test]
public fun test_new() {
    let actual = new(@0x1);

    assert!(actual.to_bytes() == @0x1.to_bytes());
    assert!(actual.length() == LENGTH);
}

#[test]
public fun test_default() {
    let default = default();

    assert!(default.bytes == @0x0);
    assert!(default.length() == LENGTH);
}

#[test]
public fun test_from_address() {
    let addr = @0x1234;
    let bytes32 = from_address(addr);
    assert!(bytes32.bytes == addr);
    assert!(bytes32.length() == LENGTH);
}
