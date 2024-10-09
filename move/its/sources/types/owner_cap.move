module its::owner_cap;
 
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
