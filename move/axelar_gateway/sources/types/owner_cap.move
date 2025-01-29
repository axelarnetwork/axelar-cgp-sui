module axelar_gateway::owner_cap {
    // -----
    // Types
    // -----
    public struct OwnerCap has key, store {
        id: UID,
    }

    public(package) fun create(ctx: &mut TxContext): OwnerCap {
        OwnerCap {
            id: object::new(ctx),
        }
    }

    /// ---------
    /// Test Only
    /// ---------
    #[test_only]
    public(package) fun destroy_for_testing(self: OwnerCap) {
        let OwnerCap { id } = self;
        id.delete();
    }
}
