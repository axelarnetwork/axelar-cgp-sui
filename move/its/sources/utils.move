module its::utils;

use std::ascii;
use sui::address;
use sui::hash::keccak256;

const LOWERCASE_START: u8 = 97;
const UPPERCASE_START: u8 = 65;
const NUMBERS_START: u8 = 48;
const SPACE: u8 = 32;
const UNDERSCORE: u8 = 95;
const ALPHABET_LENGTH: u8 = 26;
const NUMBERS_LENGTH: u8 = 10;

entry fun is_lowercase(c: u8): bool {
    c >= LOWERCASE_START && c < LOWERCASE_START + ALPHABET_LENGTH
}

entry fun is_uppercase(c: u8): bool {
    c >= UPPERCASE_START && c < UPPERCASE_START + ALPHABET_LENGTH
}

entry fun is_number(c: u8): bool {
    c >= NUMBERS_START && c < NUMBERS_START + NUMBERS_LENGTH
}

public(package) fun module_from_symbol(symbol: &ascii::String): ascii::String {
    let symbolBytes = ascii::as_bytes(symbol);
    let mut moduleName = vector[];

    let (mut i, length) = (0, vector::length(symbolBytes));
    while (is_number(*vector::borrow(symbolBytes, i))) {
        i = i + 1;
    };
    while (i < length) {
        let b = *vector::borrow(symbolBytes, i);
        if (is_lowercase(b) || is_number(b)) {
            moduleName.push_back(b);
        } else if (is_uppercase(b)) {
            moduleName.push_back(b - UPPERCASE_START + LOWERCASE_START);
        } else if (b == UNDERSCORE || b == SPACE) {
            moduleName.push_back(UNDERSCORE);
        };

        i = i + 1;
    };
    ascii::string(moduleName)
}

public(package) fun hash_coin_info(
    symbol: &ascii::String,
    decimals: &u8,
): address {
    let mut v = vector[*decimals];
    v.append(*symbol.as_bytes());
    address::from_bytes(keccak256(&v))
}

public(package) fun decode_metadata(
    mut metadata: vector<u8>,
): (u32, vector<u8>) {
    if (metadata.length() < 4) {
        (0, vector[])
    } else {
        let mut i = 0;
        let mut version: u32 = 0;
        while (i < 4) {
            version =
                (version << (8 as u8) as u32) + (metadata.remove<u8>(0) as u32);
            i = i + 1;
        };

        (version, metadata)
    }
}

public(package) fun pow(mut base: u256, mut exponent: u8): u256 {
    let mut res: u256 = 1;
    while (exponent > 0) {
        if (exponent % 2 == 0) {
            base = base * base;
            exponent = exponent / 2;
        } else {
            res = res * base;
            exponent = exponent - 1;
        }
    };
    res
}

// -----
// Tests
// -----
#[test]
fun test_get_module_from_symbol() {
    let symbol = ascii::string(b"1(TheCool1234Coin) _ []!rdt");
    std::debug::print(&module_from_symbol(&symbol));
}

#[test]
fun test_decode_metadata() {
    let (version, metadata) = decode_metadata(x"");
    assert!(version == 0);
    assert!(metadata == x"");

    let (version, metadata) = decode_metadata(x"012345");
    assert!(version == 0);
    assert!(metadata == x"");

    let (version, metadata) = decode_metadata(x"00000004");
    assert!(version == 4);
    assert!(metadata == x"");

    let (version, metadata) = decode_metadata(x"000000071ab768cf");
    assert!(version == 7);
    assert!(metadata == x"1ab768cf");
}
