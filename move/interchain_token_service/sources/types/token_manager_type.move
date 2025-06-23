module interchain_token_service::token_manager_type {
    // ---------
    // Constants
    // ---------

    // The TokenManager type values must match across chains
    // https://github.com/axelarnetwork/interchain-token-service/blob/v2.1.0/contracts/interfaces/ITokenManagerType.sol#L10
    const NATIVE_INTERCHAIN_TOKEN: u256 = 0;
    #[allow(unused_const)]
    const MINT_BURN_FROM: u256 = 1;
    const LOCK_UNLOCK: u256 = 2;
    #[allow(unused_const)]
    const LOCK_UNLOCK_FEE: u256 = 3;
    const MINT_BURN: u256 = 4;
    const MAX_TOKEN_MANAGER_TYPE: u256 = MINT_BURN;

    // ------
    // Errors
    // ------
    #[error]
    const EInvalidTokenManagerType: vector<u8> = b"invalid token manager type";

    // -----
    // Types
    // -----
    public struct TokenManagerType has copy, drop {
        token_manager_type: u256,
    }

    // ----------------
    // Public Functions
    // ----------------
    public fun lock_unlock(): TokenManagerType {
        from_u256(LOCK_UNLOCK)
    }

    public fun mint_burn(): TokenManagerType {
        from_u256(MINT_BURN)
    }

    // -----------------
    // Package Functions
    // -----------------
    /// Returns the `TokenManagerType` for the native interchain token.
    /// This should NOT be allowed to be created outside of ITS since custom tokens can't be linked via this type.
    public(package) fun native_interchain_token(): TokenManagerType {
        from_u256(NATIVE_INTERCHAIN_TOKEN)
    }

    public(package) fun from_u256(token_manager_type: u256): TokenManagerType {
        assert!(token_manager_type <= MAX_TOKEN_MANAGER_TYPE, EInvalidTokenManagerType);

        TokenManagerType {
            token_manager_type,
        }
    }

    public(package) fun to_u256(token_manager_type: TokenManagerType): u256 {
        let TokenManagerType { token_manager_type } = token_manager_type;
        token_manager_type
    }
}
