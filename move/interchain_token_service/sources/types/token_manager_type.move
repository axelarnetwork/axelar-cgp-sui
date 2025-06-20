module interchain_token_service::token_manager_type {
    // === Constancts ===
    // These have to match the enum.
    const NATIVE_INTERCHAIN_TOKEN: u256 = 0;
    const MINT_BURN_FROM: u256 = 1;
    const LOCK_UNLOCK: u256 = 2;
    const LOCK_UNLOCK_FEE: u256 = 3;
    const MINT_BURN: u256 = 4;

    // === Errors ===
    #[error]
    const EInvalidTokenManagerType: vector<u8> = b"invalid token manager type";

    // === Types ===
    public struct TokenManagerType has copy, drop {
        token_manager_type: u256,
    }

    // === Public Functions ===
    public fun native_interchain_token(): TokenManagerType {
        from_u256(NATIVE_INTERCHAIN_TOKEN)
    }

    public fun mint_burn_from(): TokenManagerType {
        from_u256(MINT_BURN_FROM)
    }

    public fun lock_unlock(): TokenManagerType {
        from_u256(LOCK_UNLOCK)
    }

    public fun lock_unlock_fee(): TokenManagerType {
        from_u256(LOCK_UNLOCK_FEE)
    }

    public fun mint_burn(): TokenManagerType {
        from_u256(MINT_BURN)
    }

    // === Package Functions ===
    public(package) fun from_u256(token_manager_type: u256): TokenManagerType {
        assert!(token_manager_type <= MINT_BURN, EInvalidTokenManagerType);
        TokenManagerType {
            token_manager_type,
        }
    }

    public(package) fun to_u256(token_manager_type: TokenManagerType): u256 {
        let TokenManagerType { token_manager_type } = token_manager_type;
        token_manager_type
    }
}
