module operators::operators {
    use sui::bag::{Self, Bag};
    use sui::vec_set::{Self, VecSet};
    use sui::event;

    // -----
    // Types
    // -----

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
        // The number of operators are small in practice, and under the Sui object size limit, so a dynamic collection doesn't need to be used
        operators: VecSet<ID>,
        // map-like collection of capabilities stored as Sui objects
        caps: Bag,
    }

    // -----
    // Error constants
    // -----

    /// When the operator is not found in the set of approved operators.
    const EOperatorNotFound: u64 = 0;

    /// When the capability is not found.
    const ECapNotFound: u64 = 1;

    // -----
    // Events
    // -----

    /// Event emitted when a new operator is added.
    public struct OperatorAdded has copy, drop {
        operator_id: ID,
    }

    /// Event emitted when an operator is removed.
    public struct OperatorRemoved has copy, drop {
        operator_id: ID,
    }

    /// Event emitted when a capability is stored.
    public struct CapabilityStored has copy, drop {
        cap_id: ID,
    }

    /// Event emitted when a capability is removed.
    public struct CapabilityRemoved has copy, drop {
        cap_id: ID,
    }

    // -----
    // Setup
    // -----

    /// Initializes the contract and transfers the `OwnerCap` to the sender.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(Operators {
            id: object::new(ctx),
            operators: vec_set::empty(),
            caps: bag::new(ctx),
        });

        let cap = OwnerCap {
            id: object::new(ctx),
        };

        transfer::transfer(cap, ctx.sender());
    }

    // ----------------
    // Public Functions
    // ----------------

    /// Adds a new operator by issuing an `OperatorCap` and storing its ID.
    public fun add_operator(self: &mut Operators, _: &OwnerCap, new_operator: address, ctx: &mut TxContext) {
        let operator_cap = OperatorCap {
            id: object::new(ctx),
        };
        let operator_id = object::id(&operator_cap);
        transfer::transfer(operator_cap, new_operator);
        self.operators.insert(operator_id);

        event::emit(OperatorAdded {
            operator_id,
        });
    }

    /// Removes an operator by ID, revoking their `OperatorCap`.
    public fun remove_operator(self: &mut Operators, _: &OwnerCap, operator_id: ID) {
        self.operators.remove(&operator_id);

        event::emit(OperatorRemoved {
            operator_id,
        });
    }

    /// Stores a capability in the `Operators` struct.
    public fun store_cap<T: key + store>(self: &mut Operators, _: &OwnerCap, cap: T) {
        let cap_id = object::id(&cap);
        self.caps.add(cap_id, cap);

        event::emit(CapabilityStored {
            cap_id,
        });
    }

    /// Allows an approved operator to borrow a capability by its ID.
    public fun borrow_cap<T: key + store>(self: &Operators, operator_cap: &OperatorCap, cap_id: ID): &T {
        let operator_id = object::id(operator_cap);

        assert!(self.operators.contains(&operator_id), EOperatorNotFound);
        assert!(self.caps.contains(cap_id), ECapNotFound);

        &self.caps[cap_id]
    }

    /// Allows an approved operator to borrow a capability by its ID.
    public fun borrow_cap_mut<T: key + store>(self: &mut Operators, operator_cap: &OperatorCap, cap_id: ID): &mut T {
        let operator_id = object::id(operator_cap);

        assert!(self.operators.contains(&operator_id), EOperatorNotFound);
        assert!(self.caps.contains(cap_id), ECapNotFound);

        &mut self.caps[cap_id]
    }

    /// Removes a capability from the `Operators` struct.
    public fun remove_cap<T: key + store>(self: &mut Operators, _: &OwnerCap, cap_id: ID): T {
        event::emit(CapabilityRemoved {
            cap_id,
        });

        self.caps.remove<ID, T>(cap_id)
    }

    // -----
    // Tests
    // -----

    #[test_only]
    fun new_operators(ctx: &mut TxContext): Operators {
        Operators {
            id: object::new(ctx),
            operators: vec_set::empty(),
            caps: bag::new(ctx),
        }
    }

    #[test_only]
    fun destroy_operators(operators: Operators) {
        let Operators { id, operators, caps } = operators;

        id.delete();
        caps.destroy_empty();

        let mut keys = operators.into_keys();

        while (!keys.is_empty()) {
            keys.pop_back();
        };
        keys.destroy_empty();
    }

    #[test_only]
    fun new_owner_cap(ctx: &mut TxContext): OwnerCap {
        OwnerCap {
            id: object::new(ctx),
        }
    }

    #[test_only]
    fun destroy_owner_cap(owner_cap: OwnerCap) {
        let OwnerCap { id } = owner_cap;
        object::delete(id);
    }

    #[test_only]
    fun new_operator_cap(self: &mut Operators, ctx: &mut TxContext): OperatorCap {
        let operator_cap = OperatorCap {
            id: object::new(ctx),
        };
        let operator_id = object::id(&operator_cap);

        self.operators.insert(operator_id);
        operator_cap
    }

    #[test_only]
    fun destroy_operator_cap(operator_cap: OperatorCap) {
        let OperatorCap { id } = operator_cap;
        object::delete(id);
    }

    #[test]
    fun test_init() {
        let ctx = &mut tx_context::dummy();
        init(ctx);

        let owner_cap = new_owner_cap(ctx);
        destroy_owner_cap(owner_cap);
    }

    #[test]
    fun test_add_and_remove_operator() {
        let ctx = &mut tx_context::dummy();
        let mut operators = new_operators(ctx);
        let owner_cap = new_owner_cap(ctx);

        let new_operator = @0x1;
        add_operator(&mut operators, &owner_cap, new_operator, ctx);
        assert!(operators.operators.keys().length() == 1, 0);

        let operator_id = operators.operators.keys()[0];
        remove_operator(&mut operators, &owner_cap, operator_id);
        assert!(operators.operators.is_empty(), 1);

        destroy_owner_cap(owner_cap);
        destroy_operators(operators);
    }

    #[test]
    fun test_store_and_remove_cap() {
        let ctx = &mut tx_context::dummy();
        let mut operators = new_operators(ctx);
        let owner_cap = new_owner_cap(ctx);
        let operator_cap = new_operator_cap(&mut operators, ctx);
        let external_cap = new_owner_cap(ctx);

        let external_id = object::id(&external_cap);

        store_cap(&mut operators, &owner_cap, external_cap);
        assert!(operators.caps.contains(external_id), 0);

        let borrowed_cap = borrow_cap<OwnerCap>(&operators, &operator_cap, external_id);
        assert!(object::id(borrowed_cap) == external_id, 1);

        let borrowed_mut_cap = borrow_cap_mut<OwnerCap>(&mut operators, &operator_cap, external_id);
        assert!(object::id(borrowed_mut_cap) == external_id, 1);

        let removed_cap = remove_cap<OwnerCap>(&mut operators, &owner_cap, external_id);
        assert!(!operators.caps.contains(external_id), 2);

        destroy_operator_cap(operator_cap);
        destroy_owner_cap(owner_cap);
        destroy_owner_cap(removed_cap);
        destroy_operators(operators);
    }

    #[test]
    #[expected_failure(abort_code = vec_set::EKeyDoesNotExist)]
    fun test_remove_operator_fail() {
        let ctx = &mut tx_context::dummy();
        let mut operators = new_operators(ctx);
        let owner_cap = new_owner_cap(ctx);

        let owner_id = object::id(&owner_cap);

        remove_operator(&mut operators, &owner_cap, owner_id);

        destroy_owner_cap(owner_cap);
        destroy_operators(operators);
    }

    #[test]
    #[expected_failure(abort_code = EOperatorNotFound)]
    fun test_borrow_cap_not_operator() {
        let ctx = &mut tx_context::dummy();
        let mut operators = new_operators(ctx);
        let owner_cap = new_owner_cap(ctx);
        let operator_cap = new_operator_cap(&mut operators, ctx);
        let external_cap = new_owner_cap(ctx);

        let external_id = object::id(&external_cap);
        let operator_id = object::id(&operator_cap);

        store_cap(&mut operators, &owner_cap, external_cap);
        remove_operator(&mut operators, &owner_cap, operator_id);

        borrow_cap<OwnerCap>(&operators, &operator_cap, external_id);

        destroy_operator_cap(operator_cap);
        destroy_owner_cap(owner_cap);
        destroy_operators(operators);
    }

    #[test]
    #[expected_failure(abort_code = ECapNotFound)]
    fun test_borrow_cap_no_such_cap() {
        let ctx = &mut tx_context::dummy();
        let mut operators = new_operators(ctx);
        let owner_cap = new_owner_cap(ctx);
        let operator_cap = new_operator_cap(&mut operators, ctx);

        let operator_id = object::id(&operator_cap);

        borrow_cap<OwnerCap>(&operators, &operator_cap, operator_id);

        destroy_operator_cap(operator_cap);
        destroy_owner_cap(owner_cap);
        destroy_operators(operators);
    }

    #[test]
    #[expected_failure(abort_code = EOperatorNotFound)]
    fun test_borrow_cap_mut_not_operator() {
        let ctx = &mut tx_context::dummy();
        let mut operators = new_operators(ctx);
        let owner_cap = new_owner_cap(ctx);
        let operator_cap = new_operator_cap(&mut operators, ctx);
        let external_cap = new_owner_cap(ctx);

        let external_id = object::id(&external_cap);
        let operator_id = object::id(&operator_cap);

        store_cap(&mut operators, &owner_cap, external_cap);
        remove_operator(&mut operators, &owner_cap, operator_id);

        borrow_cap_mut<OwnerCap>(&mut operators, &operator_cap, external_id);

        destroy_operator_cap(operator_cap);
        destroy_owner_cap(owner_cap);
        destroy_operators(operators);
    }

    #[test]
    #[expected_failure(abort_code = ECapNotFound)]
    fun test_borrow_cap_mut_no_such_cap() {
        let ctx = &mut tx_context::dummy();
        let mut operators = new_operators(ctx);
        let owner_cap = new_owner_cap(ctx);
        let operator_cap = new_operator_cap(&mut operators, ctx);

        let operator_id = object::id(&operator_cap);

        borrow_cap_mut<OwnerCap>(&mut operators, &operator_cap, operator_id);

        destroy_operator_cap(operator_cap);
        destroy_owner_cap(owner_cap);
        destroy_operators(operators);
    }

    #[test]
    #[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun test_remove_cap_fail() {
        let ctx = &mut tx_context::dummy();
        let mut operators = new_operators(ctx);
        let owner_cap = new_owner_cap(ctx);
        let operator_cap = new_operator_cap(&mut operators, ctx);
        let external_cap = new_owner_cap(ctx);

        let external_id = object::id(&external_cap);

        let removed_cap = remove_cap<OwnerCap>(&mut operators, &owner_cap, external_id);

        destroy_operator_cap(operator_cap);
        destroy_owner_cap(owner_cap);
        destroy_owner_cap(external_cap);
        destroy_owner_cap(removed_cap);
        destroy_operators(operators);
    }
}