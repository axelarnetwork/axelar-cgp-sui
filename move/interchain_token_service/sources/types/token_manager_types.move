module interchain_token_service::token_manager_types {
    // === Types ===
    public enum TokenManagerType {
        NATIVE_INTERCHAIN_TOKEN, // This type is reserved for interchain tokens deployed by ITS, and can't be used by custom token managers.
        LOCK_UNLOCK, // The token will be locked/unlocked at the token manager.
        MINT_BURN, // The token will be minted/burned on transfers. The token needs to give mint and burn permission to the token manager.
    }

    const NATIVE_INTERCHAIN_TOKEN: u8 = 0;
    const LOCK_UNLOCK: u8 = 1;
    const MINT_BURN: u8 = 2;

    public fun native_interchain_token(): u8 {
        NATIVE_INTERCHAIN_TOKEN
    }

    public fun lock_unlock(): u8 {
        LOCK_UNLOCK
    }

    public fun mint_burn(): u8 {
        MINT_BURN
    }
}
