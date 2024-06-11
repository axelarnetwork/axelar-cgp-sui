module operators::operators {
    use sui::dynamic_object_field as dof;

    /// The `OwnerCap` capability representing the owner of the contract.
    public struct OwnerCap has key, store {
        id: UID,
    }

    /// The `OperatorCap` capability representing an approved operator.
    public struct OperatorCap has key, store {
        id: UID,
    }

    /// The main `Operators` struct storing the capabilities and operator IDs.
    public struct Operators has key {
        id: UID,
        operator_ids: vector<ID>,
    }

    /// Initializes the contract and transfers the `OwnerCap` to the sender.
    fun init(ctx: &mut TxContext) {
        let owner_cap = OwnerCap {
            id: object::new(ctx),
        };
        transfer::transfer(owner_cap, tx_context::sender(ctx));
    }

    /// Adds a new operator by issuing an `OperatorCap` and storing its ID.
    public fun add_operator(operators: &mut Operators, _: &OwnerCap, new_operator: address, ctx: &mut TxContext) {
        let operator_cap = OperatorCap {
            id: object::new(ctx),
        };
        let operator_id = object::id(&operator_cap);
        transfer::transfer(operator_cap, new_operator);
        vector::push_back(&mut operators.operator_ids, operator_id);
    }

    /// Removes an operator by ID, revoking their `OperatorCap`.
    public fun remove_operator(operators: &mut Operators, _: &OwnerCap, operator_id: ID) {
        let (found, index) = vector::index_of(&operators.operator_ids, &operator_id);
        assert!(found, 0);
        vector::remove(&mut operators.operator_ids, index);
    }

    /// Stores a capability in the `Operators` struct.
    public fun store_cap<T: key + store>(operators: &mut Operators, _: &OwnerCap, cap: T) {
        let cap_id = object::id(&cap);
        dof::add(&mut operators.id, cap_id, cap);
    }

    /// Allows an approved operator to borrow a capability by its ID.
    public fun borrow_cap<T: key + store>(operators: &Operators, _: &OperatorCap, cap_id: ID): &T {
        dof::borrow(&operators.id, cap_id)
    }

    /// Removes a capability from the `Operators` struct.
    public fun remove_cap<T: key + store + drop>(operators: &mut Operators, _: &OwnerCap, cap_id: ID) {
        dof::remove<ID, T>(&mut operators.id, cap_id);
    }

}