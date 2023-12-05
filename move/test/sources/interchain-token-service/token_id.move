

module interchain_token_service::token_id {
    use std::ascii::{Self};
    use std::vector;
    use std::type_name;

    use sui::address::{Self};
    use sui::hash::{keccak256};
    use sui::bcs;

    use interchain_token_service::coin_info::{CoinInfo};

    friend interchain_token_service::service;

    // address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id"))));
    const PREFIX_SUI_TOKEN_ID: u256 = 0x72efd4f4a47bdb9957673d9d0fabc22cad1544bc247ac18367ac54985919bfa3;
    

    struct TokenId has store, copy, drop {
        id: address
    }

    struct UnregisteredTokenId has store, copy, drop {
        id: address
    }

    public fun from_address(id: address): TokenId {
        TokenId{ id }
    }
    public fun from_u256(id: u256): TokenId {
        TokenId{ id: address::from_u256(id) }
    }

    public fun to_u256(token_id: &TokenId): u256 {
        address::to_u256(token_id.id)
    }

    public (friend) fun from_coin_info<T>(coin_info: &CoinInfo<T>): TokenId {
        let vec = address::to_bytes(address::from_u256(PREFIX_SUI_TOKEN_ID));
        vector::append(&mut vec, bcs::to_bytes(coin_info));
        TokenId { id: address::from_bytes(keccak256(&vec)) }
    }

    public (friend) fun unregistered_token_id<T>(decimals: u8): UnregisteredTokenId {
        let module_name = type_name::get_module(&type_name::get<T>());
        let v = vector::singleton(decimals);
        vector::append<u8>(&mut v, *ascii::as_bytes(&module_name));
        let id = address::from_bytes(keccak256(&v));
        UnregisteredTokenId { id }
    }

    #[test]
    fun test() {
        use std::debug;
        use std::string;
        use interchain_token_service::coin_info;

        let prefix = address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id"))));
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