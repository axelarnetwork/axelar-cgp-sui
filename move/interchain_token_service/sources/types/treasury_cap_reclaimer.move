module interchain_token_service::treasury_cap_reclaimer {
    // -----
    // Types
    // -----
    public struct TreasuryCapReclaimer<phantom T> has key, store {
        id: UID,
    }

    public(package) fun create<T>(ctx: &mut TxContext): TreasuryCapReclaimer<T> {
        TreasuryCapReclaimer<T> {
            id: object::new(ctx),
        }
    }

    // Maybe make this entry to allow users to destroy this.
    public(package) fun destroy<T>(self: TreasuryCapReclaimer<T>) {
        let TreasuryCapReclaimer { id } = self;
        id.delete();
    }
}
