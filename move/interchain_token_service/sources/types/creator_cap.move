module interchain_token_service::creator_cap {
    // -----
    // Types
    // -----
    public struct CreatorCap has key, store {
        id: UID,
    }

    public(package) fun create(ctx: &mut TxContext): CreatorCap {
        CreatorCap {
            id: object::new(ctx),
        }
    }

    public(package) fun destroy(self: CreatorCap) {
        let CreatorCap { id } = self;
        id.delete();
    }
}
