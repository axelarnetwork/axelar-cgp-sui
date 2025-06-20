module interchain_token_service::token_manager_types {
    // === Types ===
    public enum TokenManagerType {
        NATIVE_INTERCHAIN_TOKEN, // This type is reserved for interchain tokens deployed by ITS, and can't be used by custom token managers.
        LOCK_UNLOCK, // The token will be locked/unlocked at the token manager.
        MINT_BURN, // The token will be minted/burned on transfers. The token needs to give mint and burn permission to the token manager.
    }

    // === Constants ===
    const NATIVE_INTERCHAIN_TOKEN: u8 = 0;
    const LOCK_UNLOCK: u8 = 1;
    const MINT_BURN: u8 = 2;

    // === Errors ===
    #[error]
    const ETokenManagerTypeUnsupported: vector<u8> = b"token manager type out of bounds";

    public fun native_interchain_token(): u8 {
        NATIVE_INTERCHAIN_TOKEN
    }

    public fun lock_unlock(): u8 {
        LOCK_UNLOCK
    }

    public fun mint_burn(): u8 {
        MINT_BURN
    }

    public fun should_have_treasry_cap_for_link_token(token_manager_type: u8): bool {
        assert!(token_manager_type != NATIVE_INTERCHAIN_TOKEN && token_manager_type <= MINT_BURN, ETokenManagerTypeUnsupported);

        token_manager_type == MINT_BURN
    }

    // === Tests ===
    #[test]
    #[expected_failure(abort_code=ETokenManagerTypeUnsupported)]
    fun test_should_have_treasry_cap_for_link_token_native_interchain() {
        should_have_treasry_cap_for_link_token(0);
    }

    #[test]
    #[expected_failure(abort_code=ETokenManagerTypeUnsupported)]
    fun test_should_have_treasry_cap_for_link_token_non_existent() {
        should_have_treasry_cap_for_link_token(100);
    }
}
