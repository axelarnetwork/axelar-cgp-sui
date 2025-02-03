module interchain_token_service::operator_cap {
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
}
