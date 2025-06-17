module interchain_token_service::token_id {
    use axelar_gateway::{bytes32::Bytes32, channel::Channel};
    use interchain_token_service::{coin_info::CoinInfo, coin_management::CoinManagement};
    use std::{ascii, string::String, type_name};
    use sui::{address, bcs, hash::keccak256};

    // address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id"))));
    const PREFIX_SUI_TOKEN_ID: u256 = 0x72efd4f4a47bdb9957673d9d0fabc22cad1544bc247ac18367ac54985919bfa3;

    // address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-custom-token-id"))));
    const PREFIX_SUI_CUSTOM_TOKEN_ID: u256 = 0xca5638c222d80aeaee69358fc5c11c4b3862bd9becdce249fcab9c679dbad781;

    // address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-unregistered-interchain-token-id"))));
    const PREFIX_UNREGISTERED_INTERCHAIN_TOKEN_ID: u256 = 0xe95d1bd561a97aa5be610da1f641ee43729dd8c5aab1c7f8e90ea6d904901a50;

    public struct TokenId has copy, drop, store {
        id: address,
    }

    public struct UnregisteredTokenId has copy, drop, store {
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
        chain_name_hash: &Bytes32,
        name: &String,
        symbol: &ascii::String,
        decimals: &u8,
        has_metadata: &bool,
        has_treasury: &bool,
    ): TokenId {
        let mut vec = address::from_u256(PREFIX_SUI_TOKEN_ID).to_bytes();
        vec.append(bcs::to_bytes(chain_name_hash));
        vec.append(bcs::to_bytes(&type_name::get<T>()));
        vec.append(bcs::to_bytes(name));
        vec.append(bcs::to_bytes(symbol));
        vec.append(bcs::to_bytes(decimals));
        vec.append(bcs::to_bytes(has_metadata));
        vec.append(bcs::to_bytes(has_treasury));
        TokenId { id: address::from_bytes(keccak256(&vec)) }
    }

    public(package) fun from_coin_data<T>(
        chain_name_hash: &Bytes32,
        coin_info: &CoinInfo<T>,
        coin_management: &CoinManagement<T>,
    ): TokenId {
        from_info<T>(
            chain_name_hash,
            &coin_info.name(),
            &coin_info.symbol(),
            &coin_info.decimals(),
            &option::is_some(coin_info.metadata()),
            &coin_management.has_treasury_cap(),
        )
    }

    public(package) fun custom(chain_name_hash: &Bytes32, deployer: &Channel, salt: &Bytes32): TokenId {
        let mut vec = address::from_u256(PREFIX_SUI_CUSTOM_TOKEN_ID).to_bytes();
        vec.append(bcs::to_bytes(chain_name_hash));
        vec.append(bcs::to_bytes(deployer));
        vec.append(bcs::to_bytes(salt));
        TokenId { id: address::from_bytes(keccak256(&vec)) }
    }

    public fun unregistered_token_id(symbol: &ascii::String, decimals: u8): UnregisteredTokenId {
        let prefix = PREFIX_UNREGISTERED_INTERCHAIN_TOKEN_ID;
        let mut v = bcs::to_bytes(&prefix);
        v.push_back(decimals);
        v.append(*ascii::as_bytes(symbol));
        let id = address::from_bytes(keccak256(&v));
        UnregisteredTokenId { id }
    }

    // === Tests ===
    #[test]
    fun test() {
        use std::string;
        use interchain_token_service::coin_info;

        let prefix = address::to_u256(
            address::from_bytes(
                keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id")),
            ),
        );
        assert!(prefix == PREFIX_SUI_TOKEN_ID);

        let name = string::utf8(b"Name");
        let symbol = ascii::string(b"Symbol");
        let decimals: u8 = 9;
        let coin_info = coin_info::from_info<String>(
            name,
            symbol,
            decimals,
        );
        let mut vec = address::from_u256(PREFIX_SUI_TOKEN_ID).to_bytes();

        vec.append<u8>(bcs::to_bytes<CoinInfo<String>>(&coin_info));
        coin_info.drop();
    }
}
