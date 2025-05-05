module gas_service::operator_cap {
    // -----
    // Types
    // -----
    public struct OperatorCap has key, store {
        id: UID,
    }

    public(package) fun create(ctx: &mut TxContext): OperatorCap {
        OperatorCap {
            id: object::new(ctx),
        }
    }

    // ---------
    // Test Only
    // ---------
    #[test_only]
    public(package) fun destroy_cap(self: OperatorCap) {
        let OperatorCap { id } = self;
        id.delete();
    }
}
