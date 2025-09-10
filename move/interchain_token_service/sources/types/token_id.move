module interchain_token_service::token_id {
    use axelar_gateway::{bytes32::Bytes32, channel::Channel};
    use interchain_token_service::{coin_info::CoinInfo, coin_management::CoinManagement, token_manager_type::TokenManagerType};
    use std::{ascii, string::String, type_name};
    use sui::{address, bcs, hash::keccak256};

    // address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id"))));
    const PREFIX_SUI_TOKEN_ID: u256 = 0x72efd4f4a47bdb9957673d9d0fabc22cad1544bc247ac18367ac54985919bfa3;

    // address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-custom-token-id"))));
    const PREFIX_SUI_CUSTOM_TOKEN_ID: u256 = 0xca5638c222d80aeaee69358fc5c11c4b3862bd9becdce249fcab9c679dbad782;

    // address::from_bytes(keccak256(&b"prefix-unregistered-interchain-token-id"));
    const PREFIX_UNREGISTERED_INTERCHAIN_TOKEN_ID: u256 = 0xe95d1bd561a97aa5be610da1f641ee43729dd8c5aab1c7f8e90ea6d904901a50;

    // address::to_u256(address::from_bytes(keccak256(&b"prefix-unlinked-interchain-token-id")));
    const PREFIX_UNLINKED_INTERCHAIN_TOKEN_ID: u256 = 0x875e1b812d4076e924370972217812584b40adad67b8f43380d25b27f048221a;

    public struct TokenId has copy, drop, store {
        id: address,
    }

    public struct UnlinkedTokenId has copy, drop, store {
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
        vec.append(bcs::to_bytes(&type_name::with_defining_ids<T>()));
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
        has_metadata: bool,
    ): TokenId {
        from_info<T>(
            chain_name_hash,
            &coin_info.name(),
            &coin_info.symbol(),
            &coin_info.decimals(),
            &has_metadata,
            &coin_management.has_treasury_cap(),
        )
    }

    public(package) fun custom_token_id(chain_name_hash: &Bytes32, deployer: &Channel, salt: &Bytes32): TokenId {
        let mut vec = address::from_u256(PREFIX_SUI_CUSTOM_TOKEN_ID).to_bytes();
        vec.append(bcs::to_bytes(chain_name_hash));
        vec.append(bcs::to_bytes(&deployer.id()));
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

    public(package) fun unlinked_token_id<T>(token_id: TokenId, token_manager_type: TokenManagerType): UnlinkedTokenId {
        let prefix = PREFIX_UNLINKED_INTERCHAIN_TOKEN_ID;
        let mut v = bcs::to_bytes(&prefix);
        v.append(bcs::to_bytes(&token_id));
        v.append(bcs::to_bytes(&type_name::with_defining_ids<T>()));
        v.append(bcs::to_bytes(&token_manager_type.to_u256()));
        let id = address::from_bytes(keccak256(&v));
        UnlinkedTokenId { id }
    }

    // === Test Only ===
    #[test_only]
    use axelar_gateway::channel;
    #[test_only]
    use interchain_token_service::coin::COIN;

    #[test_only]
    public fun to_address(token_id: TokenId): address {
        token_id.id
    }

    // === Tests ===
    #[test]
    fun test_prefixes() {
        let prefix_sui_token_id = address::to_u256(address::from_bytes(keccak256(&bcs::to_bytes<vector<u8>>(&b"prefix-sui-token-id"))));
        assert!(prefix_sui_token_id == PREFIX_SUI_TOKEN_ID);

        let prefix_custom_token_id = address::to_u256(
            address::from_bytes(keccak256(&b"prefix-sui-custom-token-id")),
        );
        assert!(prefix_custom_token_id == PREFIX_SUI_CUSTOM_TOKEN_ID);

        let prefix_unregistered_interchain_token_id = address::to_u256(
            address::from_bytes(keccak256(&b"prefix-unregistered-interchain-token-id")),
        );
        assert!(prefix_unregistered_interchain_token_id == PREFIX_UNREGISTERED_INTERCHAIN_TOKEN_ID);

        let prefix_unlinked_interchain_token_id = address::to_u256(address::from_bytes(keccak256(&b"prefix-unlinked-interchain-token-id")));
        assert!(prefix_unlinked_interchain_token_id == PREFIX_UNLINKED_INTERCHAIN_TOKEN_ID);
    }

    #[test]
    fun test_from_info() {
        let chain_name_hash = &axelar_gateway::bytes32::new(address::from_u256(0x1234));
        let name = &std::string::utf8(b"name");
        let symbol = &ascii::string(b"symbol");
        let decimals = &9;
        let has_metadata = &true;
        let has_treasury = &false;

        let mut vec = address::from_u256(PREFIX_SUI_TOKEN_ID).to_bytes();
        vec.append(bcs::to_bytes(chain_name_hash));
        vec.append(bcs::to_bytes(&type_name::with_defining_ids<COIN>()));
        vec.append(bcs::to_bytes(name));
        vec.append(bcs::to_bytes(symbol));
        vec.append(bcs::to_bytes(decimals));
        vec.append(bcs::to_bytes(has_metadata));
        vec.append(bcs::to_bytes(has_treasury));
        let calculated_token_id = TokenId { id: address::from_bytes(keccak256(&vec)) };

        let token_id = from_info<COIN>(chain_name_hash, name, symbol, decimals, has_metadata, has_treasury);

        assert!(token_id == calculated_token_id);
    }

    #[test]
    fun test_custom_token_id() {
        let ctx = &mut sui::tx_context::dummy();

        let chain_name_hash = &axelar_gateway::bytes32::new(address::from_u256(0x1234));
        let deployer = channel::new(ctx);
        let salt = &axelar_gateway::bytes32::new(address::from_u256(0x5678));

        let mut vec = address::from_u256(PREFIX_SUI_CUSTOM_TOKEN_ID).to_bytes();
        vec.append(bcs::to_bytes(chain_name_hash));
        vec.append(bcs::to_bytes(&deployer.id()));
        vec.append(bcs::to_bytes(salt));

        let calculated_token_id = TokenId { id: address::from_bytes(keccak256(&vec)) };

        let token_id = custom_token_id(chain_name_hash, &deployer, salt);

        assert!(calculated_token_id == token_id);

        deployer.destroy();
    }

    #[test]
    fun test_unregistered_token_id() {
        let symbol = &ascii::string(b"symbol");
        let decimals = 9;
        let prefix = PREFIX_UNREGISTERED_INTERCHAIN_TOKEN_ID;
        let mut v = bcs::to_bytes(&prefix);
        v.push_back(decimals);
        v.append(*ascii::as_bytes(symbol));
        let id = address::from_bytes(keccak256(&v));

        let calculated_token_id = UnregisteredTokenId { id };

        let token_id = unregistered_token_id(symbol, decimals);

        assert!(token_id == calculated_token_id);
    }

    #[test]
    fun test_unlinked_token_id() {
        let token_manager_type = interchain_token_service::token_manager_type::lock_unlock();
        let token_id = from_u256(1234);

        let prefix = PREFIX_UNLINKED_INTERCHAIN_TOKEN_ID;
        let mut v = bcs::to_bytes(&prefix);
        v.append(bcs::to_bytes(&token_id));
        v.append(bcs::to_bytes(&type_name::with_defining_ids<COIN>()));
        v.append(bcs::to_bytes(&token_manager_type.to_u256()));
        let id = address::from_bytes(keccak256(&v));

        let calculated_token_id = UnlinkedTokenId { id };

        let unlinked_token_id = unlinked_token_id<COIN>(token_id, token_manager_type);

        assert!(unlinked_token_id == calculated_token_id);
    }
}
