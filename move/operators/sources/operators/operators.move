module operators::operators {
    use sui::bag::{Self, Bag};

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
        operator_ids: vector<ID>,
        caps: Bag,
    }

    // -----
    // Setup
    // -----

    /// Initializes the contract and transfers the `OwnerCap` to the sender.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(Operators {
            id: object::new(ctx),
            operator_ids: vector::empty(),
            caps: bag::new(ctx),
        });

        transfer::public_transfer(OwnerCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx));
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
        transfer::public_transfer(operator_cap, new_operator);
        self.operator_ids.push_back(operator_id);
    }

    /// Removes an operator by ID, revoking their `OperatorCap`.
    public fun remove_operator(self: &mut Operators, _: &OwnerCap, operator_id: ID) {
        let (found, index) = self.operator_ids.index_of(&operator_id);
        assert!(found, 0);
        self.operator_ids.remove(index);
    }

    /// Stores a capability in the `Operators` struct.
    public fun store_cap<T: key + store>(self: &mut Operators, _: &OwnerCap, cap: T) {
        let cap_id = object::id(&cap);
        self.caps.add(cap_id, cap);
    }

    /// Allows an approved operator to borrow a capability by its ID.
    public fun borrow_cap<T: key + store>(self: &Operators, operator_cap: &OperatorCap, cap_id: ID): &T {
        let operator_id = object::id(operator_cap);

        assert!(self.operator_ids.contains(&operator_id), 0);
        assert!(self.caps.contains(cap_id), 1);

        &self.caps[cap_id]
    }

    /// Removes a capability from the `Operators` struct.
    public fun transfer_cap<T: key + store>(self: &mut Operators, _: &OwnerCap, cap_id: ID, new_holder: address) {
        transfer::public_transfer(self.caps.remove<ID, T>(cap_id), new_holder);
    }

    // -----
    // Tests
    // -----

    #[test_only]
    fun new_operators(ctx: &mut TxContext): Operators {
        Operators {
            id: object::new(ctx),
            operator_ids: vector::empty(),
            caps: bag::new(ctx),
        }
    }

    #[test_only]
    fun destroy_operators(operators: Operators) {
        let Operators { id, mut operator_ids, caps } = operators;

        id.delete();
        caps.destroy_empty();

        while (!operator_ids.is_empty()) {
            operator_ids.pop_back();
        };
        operator_ids.destroy_empty();
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

        self.operator_ids.push_back(operator_id);
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
        assert!(operators.operator_ids.length() == 1, 0);

        let operator_id = operators.operator_ids[0];
        remove_operator(&mut operators, &owner_cap, operator_id);
        assert!(operators.operator_ids.is_empty(), 1);

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

        transfer_cap<OwnerCap>(&mut operators, &owner_cap, external_id, @0x3);
        assert!(!operators.caps.contains(external_id), 2);

        destroy_operator_cap(operator_cap);
        destroy_owner_cap(owner_cap);
        destroy_operators(operators);
    }


    #[test]
    #[expected_failure(abort_code = 0, location = operators::operators)]
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
    #[expected_failure(abort_code = 0, location = operators::operators)]
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
    #[expected_failure(abort_code = 1, location = operators::operators)]
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
}