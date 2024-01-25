

module its::token_id {
    use std::ascii;
    use std::vector;
    use std::string::String;
    use std::type_name;
    use std::option;

    use sui::hash::keccak256;
    use sui::address;
    use sui::bcs;

    use its::coin_info::{Self, CoinInfo};
    use its::coin_management::{Self, CoinManagement};

    friend its::service;

    // address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id"))));
    const PREFIX_SUI_TOKEN_ID: u256 = 0x72efd4f4a47bdb9957673d9d0fabc22cad1544bc247ac18367ac54985919bfa3;

    struct TokenId has store, copy, drop {
        id: address
    }

    struct UnregisteredTokenId has store, copy, drop {
        id: address
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
        has_treasury: &bool
    ): TokenId {
        let vec = address::to_bytes(address::from_u256(PREFIX_SUI_TOKEN_ID));
        vector::append(&mut vec, bcs::to_bytes(&type_name::get<T>()));
        vector::append(&mut vec, bcs::to_bytes(name));
        vector::append(&mut vec, bcs::to_bytes(symbol));
        vector::append(&mut vec, bcs::to_bytes(decimals));
        vector::append(&mut vec, bcs::to_bytes(has_metadata));
        vector::append(&mut vec, bcs::to_bytes(has_treasury));
        TokenId { id: address::from_bytes(keccak256(&vec)) }
    }

    public(friend) fun from_coin_data<T>(
        coin_info: &CoinInfo<T>, coin_management: &CoinManagement<T>
    ): TokenId {
        from_info<T>(
            &coin_info::name(coin_info),
            &coin_info::symbol(coin_info),
            &coin_info::decimals(coin_info),
            &option::is_some(coin_info::metadata(coin_info)),
            &coin_management::has_capability(coin_management),
        )
    }

    public fun unregistered_token_id(
        symbol: &ascii::String, decimals: u8
    ): UnregisteredTokenId {
        let v = vector[decimals];
        vector::append(&mut v, *ascii::as_bytes(symbol));
        let id = address::from_bytes(keccak256(&v));
        UnregisteredTokenId { id }
    }

    #[test]
    fun test() {
        use std::debug;
        use std::string;
        use its::coin_info;

        let prefix = address::to_u256(
            address::from_bytes(
                keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id"))
            )
        );
        assert!(prefix == PREFIX_SUI_TOKEN_ID, 5);

        let name = string::utf8(b"Name");
        let symbol = ascii::string(b"Symbol");
        let decimals: u8 = 56;
        let coin_info = coin_info::from_info<String>(name, symbol, decimals);
        let vec = address::to_bytes(address::from_u256(PREFIX_SUI_TOKEN_ID));
        vector::append<u8>(&mut vec, bcs::to_bytes<CoinInfo<String>>(&coin_info));
        debug::print<address>(&address::from_u256(PREFIX_SUI_TOKEN_ID));
        debug::print<vector<u8>>(&vec);
        coin_info::drop(coin_info);
    }
}
