module its::token_id;

use its::coin_info::CoinInfo;
use its::coin_management::CoinManagement;
use std::ascii;
use std::string::String;
use std::type_name;
use sui::address;
use sui::bcs;
use sui::hash::keccak256;

// address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id"))));
const PREFIX_SUI_TOKEN_ID: u256 =
    0x72efd4f4a47bdb9957673d9d0fabc22cad1544bc247ac18367ac54985919bfa3;

public struct TokenId has store, copy, drop {
    id: address,
}

public struct UnregisteredTokenId has store, copy, drop {
    id: address,
}

public fun from_address(id: address): TokenId {
    TokenId { id }
}

public fun from_u256(id: u256): TokenId {
    TokenId { id: address::from_u256(id) }
}

public fun to_u256(token_id: &TokenId): u256 {
    address::to_u256(token_id.id)
}

public fun from_info<T>(
    name: &String,
    symbol: &ascii::String,
    decimals: &u8,
    has_metadata: &bool,
    has_treasury: &bool,
): TokenId {
    let mut vec = address::from_u256(PREFIX_SUI_TOKEN_ID).to_bytes();
    vec.append(bcs::to_bytes(&type_name::get<T>()));
    vec.append(bcs::to_bytes(name));
    vec.append(bcs::to_bytes(symbol));
    vec.append(bcs::to_bytes(decimals));
    vec.append(bcs::to_bytes(has_metadata));
    vec.append(bcs::to_bytes(has_treasury));
    TokenId { id: address::from_bytes(keccak256(&vec)) }
}

public(package) fun from_coin_data<T>(
    coin_info: &CoinInfo<T>,
    coin_management: &CoinManagement<T>,
): TokenId {
    from_info<T>(
        &coin_info.name(),
        &coin_info.symbol(),
        &coin_info.decimals(),
        &option::is_some(coin_info.metadata()),
        &coin_management.has_capability(),
    )
}

public fun unregistered_token_id(
    symbol: &ascii::String,
    decimals: u8,
): UnregisteredTokenId {
    let mut v = vector[decimals];
    v.append(*ascii::as_bytes(symbol));
    let id = address::from_bytes(keccak256(&v));
    UnregisteredTokenId { id }
}

// === Tests ===
#[test]
fun test() {
    use std::string;
    use its::coin_info;

    let prefix = address::to_u256(
        address::from_bytes(
            keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id")),
        ),
    );
    assert!(prefix == PREFIX_SUI_TOKEN_ID);

    let name = string::utf8(b"Name");
    let symbol = ascii::string(b"Symbol");
    let decimals: u8 = 9;
    let remote_decimals: u8 = 18;
    let coin_info = coin_info::from_info<String>(
        name,
        symbol,
        decimals,
        remote_decimals,
    );
    let mut vec = address::from_u256(PREFIX_SUI_TOKEN_ID).to_bytes();

    vec.append<u8>(bcs::to_bytes<CoinInfo<String>>(&coin_info));
    coin_info.drop();
}
