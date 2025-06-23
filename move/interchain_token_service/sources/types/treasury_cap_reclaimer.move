module interchain_token_service::treasury_cap_reclaimer {
    use interchain_token_service::token_id::TokenId;

    // -----
    // Types
    // -----
    /// Allow a user to reclaim a `TreasuryCap` from ITS.
    /// Phantom type `T` is the type of the token that the `TreasuryCap` is being reclaimed for.
    public struct TreasuryCapReclaimer<phantom T> has key, store {
        id: UID,
        /// The `token_id` for which the `TreasuryCap` is being stored by ITS
        token_id: TokenId,
    }

    public(package) fun create<T>(token_id: TokenId, ctx: &mut TxContext): TreasuryCapReclaimer<T> {
        TreasuryCapReclaimer<T> {
            id: object::new(ctx),
            token_id,
        }
    }

    public(package) fun token_id<T>(self: &TreasuryCapReclaimer<T>): TokenId {
        self.token_id
    }

    // Maybe make this an entry function to allow users to destroy this.
    public(package) fun destroy<T>(self: TreasuryCapReclaimer<T>) {
        let TreasuryCapReclaimer { id, token_id: _ } = self;
        id.delete();
    }
}
