module example::operators {
    use axelar_gateway::channel::Channel;
    use interchain_token_service::{interchain_token_service::InterchainTokenService, token_id::TokenId};
    use operators::operators::{OperatorCap, Operators};
    use sui::coin::Coin;

    // -------
    // Structs
    // -------
    public struct MultiMinter has key {
        id: UID,
        // Approach 1
        distributor_cap: Option<Channel>,
        // Approach 2
        operator_cap: Option<OperatorCap>,
        distributor_cap_id: Option<ID>,
    }

    public struct OwnerCap has key, store {
        id: UID,
    }

    // -----
    // Setup
    // -----
    fun init(ctx: &mut TxContext) {
        transfer::share_object(MultiMinter {
            id: object::new(ctx),
            distributor_cap: option::none(),
            operator_cap: option::none(),
            distributor_cap_id: option::none(),
        });

        transfer::public_transfer(
            OwnerCap {
                id: object::new(ctx),
            },
            ctx.sender(),
        );
    }

    // -----
    // Public Functions
    // -----

    /// Requirements: Only ITS and this package need to have mint capability over the Coin simultaneously.
    /// Setup: When registering the coin with ITS, the `TreasuryCap` is provided to ITS, and ITS returns a distributor `Channel` capability,
    /// along with `TreasuryCapReclaimer` that can reclaim the treasury cap to stop bridging.
    /// The Distributor `Channel` cap allows an additional action to mint the coin.
    /// This should be stored in this package's object by calling the `add_distributor_cap`._owner_cap
    ///
    /// `mint_as_distributor` can be called by this package to mint the coin.
    public fun mint<T>(self: &MultiMinter, its: &mut InterchainTokenService, token_id: TokenId, amount: u64, ctx: &mut TxContext): Coin<T> {
        let coin = its.mint_as_distributor<T>(self.distributor_cap.borrow(), token_id, amount, ctx);
        coin
    }

    /// After registering the coin with ITS, store the distributor `Channel` capability here.
    public fun add_distributor_cap(self: &mut MultiMinter, _owner_cap: &OwnerCap, distributor_cap: Channel) {
        self.distributor_cap.fill(distributor_cap);
    }

    /// Acquire the distributor `Channel` capability from the `MultiMinter` object.
    public fun remove_distributor_cap(self: &mut MultiMinter, _owner_cap: &OwnerCap): Channel {
        self.distributor_cap.extract()
    }

    /// Requirements: ITS, this package, and other addresses need to have mint capability over the Coin simultaneously.
    /// Setup: This is a more demanding requirement and thus the `Operators` contract can be used to give multiple operators the ability to mint.
    /// When registering the coin with ITS, the `TreasuryCap` is provided to ITS, and ITS returns a distributor `Channel` capability,
    /// along with `TreasuryCapReclaimer` that can reclaim the treasury cap to stop bridging.
    /// The Distributor `Channel` cap allows an additional action to mint the coin.
    ///
    /// An instance of the `Operators` contract needs to be deployed. The `Channel` capability then needs to be stored by calling `store_cap`.
    /// The `OperatorCap` needs to be stored by calling `add_operator_cap`, along with `Channel` capability ID.
    ///
    /// Now, using the `OperatorCap`, the `Channel` cap can be loaned from the `Operators` contract.
    /// Then, it can be used to mint the coin via ITS, and the loaned `Channel` cap can be returned to the `Operators` contract atomically.
    public fun mint_as_operator<T>(
        self: &mut MultiMinter,
        its: &mut InterchainTokenService,
        operators: &mut Operators,
        token_id: TokenId,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        let (distributor_cap, borrow) = operators.loan_cap<Channel>(self.operator_cap.borrow(), *self.distributor_cap_id.borrow(), ctx);
        let coin = its.mint_as_distributor<T>(&distributor_cap, token_id, amount, ctx);
        operators.restore_cap(self.operator_cap.borrow(), distributor_cap, borrow);
        coin
    }

    /// Store the `OperatorCap` capability that was given by the `Operators` contract.
    public fun add_operator_cap(self: &mut MultiMinter, _owner_cap: &OwnerCap, operator_cap: OperatorCap, distributor_cap_id: ID) {
        self.distributor_cap_id.fill(distributor_cap_id);
        self.operator_cap.fill(operator_cap);
    }

    /// Acquire the `OperatorCap` capability from the `MultiMinter` object.
    public fun remove_operator_cap(self: &mut MultiMinter, _owner_cap: &OwnerCap): OperatorCap {
        let _ = self.distributor_cap_id.extract();
        self.operator_cap.extract()
    }

    // Test Only
    #[test_only]
    use operators::operators;
    #[test_only]
    use interchain_token_service::{interchain_token_service, coin_management, coin};
    #[test_only]
    use sui::test_utils;
    #[test_only]
    use axelar_gateway::{channel, bytes32};

    #[test_only]
    fun create_for_testing(ctx: &mut TxContext): (MultiMinter, OwnerCap) {
        let multiminter = MultiMinter {
            id: object::new(ctx),
            distributor_cap: option::none(),
            operator_cap: option::none(),
            distributor_cap_id: option::none(),
        };

        (multiminter, OwnerCap { id: object::new(ctx) })
    }

    // Tests
    #[test]
    fun test_mint() {
        let ctx = &mut tx_context::dummy();
        let mut its = interchain_token_service::create_for_testing(ctx);
        let amount = 12345;

        // Create and register coin
        let (treasury_cap, coin_metadata) = coin::create_treasury_and_metadata(b"TOKEN", 9, ctx);
        let mut coin_management = coin_management::new_with_cap(treasury_cap);

        let distributor = channel::new(ctx);
        coin_management.add_distributor(distributor.to_address());

        let deployer = channel::new(ctx);
        let salt = bytes32::from_address(@0x1234);
        let (token_id, treasury_cap_reclaimer) = its.register_custom_coin(
            &deployer,
            salt,
            &coin_metadata,
            coin_management,
            ctx,
        );

        let (mut multiminter, owner) = create_for_testing(ctx);

        // Add distributor cap directly to the multiminter
        multiminter.add_distributor_cap(&owner, distributor);

        let coin = multiminter.mint<coin::COIN>(
            &mut its,
            token_id,
            amount,
            ctx,
        );

        assert!(coin.value() == amount);

        test_utils::destroy(its);
        test_utils::destroy(deployer);
        test_utils::destroy(coin_metadata);
        test_utils::destroy(multiminter.remove_distributor_cap(&owner));
        test_utils::destroy(coin);
        test_utils::destroy(treasury_cap_reclaimer);
        test_utils::destroy(owner);
        test_utils::destroy(multiminter);
    }

    #[test]
    fun test_mint_as_operator() {
        let ctx = &mut tx_context::dummy();
        let mut operators = operators::new_operators(ctx);
        let owner_cap = operators::new_owner_cap(ctx);
        let operator_cap = operators.new_operator_cap(ctx);

        let distributor = channel::new(ctx);
        let distributor_address = distributor.to_address();
        let distributor_id = distributor.id();
        operators.store_cap(&owner_cap, distributor);

        let mut its = interchain_token_service::create_for_testing(ctx);
        let amount = 12345;

        // Create and register coin
        let (treasury_cap, coin_metadata) = coin::create_treasury_and_metadata(b"TOKEN", 9, ctx);
        let mut coin_management = coin_management::new_with_cap(treasury_cap);
        coin_management.add_distributor(distributor_address);

        let deployer = channel::new(ctx);
        let salt = bytes32::from_address(@0x1234);
        let (token_id, treasury_cap_reclaimer) = its.register_custom_coin(
            &deployer,
            salt,
            &coin_metadata,
            coin_management,
            ctx,
        );

        let (mut multiminter, owner) = create_for_testing(ctx);

        multiminter.add_operator_cap(&owner, operator_cap, distributor_id);

        let coin = multiminter.mint_as_operator<coin::COIN>(
            &mut its,
            &mut operators,
            token_id,
            amount,
            ctx,
        );

        assert!(coin.value() == amount);

        owner_cap.destroy_owner_cap();
        test_utils::destroy(its);
        test_utils::destroy(operators);
        test_utils::destroy(deployer);
        test_utils::destroy(coin_metadata);
        test_utils::destroy(multiminter.remove_operator_cap(&owner));
        test_utils::destroy(coin);
        test_utils::destroy(treasury_cap_reclaimer);
        test_utils::destroy(owner);
        test_utils::destroy(multiminter);
    }
}
