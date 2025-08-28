module example::operators {
    use axelar_gateway::channel::Channel;
    use interchain_token_service::{
        interchain_token_service::InterchainTokenService,
        token_id::TokenId,
    };
    use operators::operators::{OperatorCap, Operators};
    use sui::coin::Coin;

    // Public Functions

    // This can be simplified by removing the need for the token_id to be an argument by exposing it in the treasury_cap_reclaimer
    public fun mint<T>(
        its: &mut InterchainTokenService,
        operators: &mut Operators,
        operator_cap: &OperatorCap,
        cap_id: ID,
        token_id: TokenId,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        let (distributor_cap, borrow) = operators.loan_cap<Channel>(operator_cap, cap_id, ctx);
        let coin = its.mint_as_distributor<T>(&distributor_cap, token_id, amount, ctx);
        operators.restore_cap(operator_cap, distributor_cap, borrow);
        coin
    }

    // Test Only
    #[test_only]
    use operators::operators;
    #[test_only] 
    use interchain_token_service::{
        interchain_token_service,
        coin_management,
    };
    #[test_only] 
    use sui::{
        test_utils,
        coin::{Self, TreasuryCap, CoinMetadata},
    };
    #[test_only] 
    use axelar_gateway::{
        channel,
        bytes32,
    };

    #[test_only] 
    public struct OPERATORS has drop {}

    #[test_only]
    fun create_test_coin(ctx: &mut TxContext): (TreasuryCap<OPERATORS>, CoinMetadata<OPERATORS>) {
        coin::create_currency(
            OPERATORS {},
            9,
            b"OPERATORS",
            b"Operators Example Coin",
            b"",
            option::none(),
            ctx,
        )
    }

    // Tests
    #[test]
    fun test_mint() {
        let ctx = &mut tx_context::dummy();
        let mut operators = operators::new_operators(ctx);
        let owner_cap = operators::new_owner_cap(ctx);
        let operator_cap = operators.new_operator_cap(ctx);

        let distributor = channel::new(ctx);
        let distributor_id = distributor.id();
        operators.store_cap(&owner_cap, distributor);

        let mut its = interchain_token_service::create_for_testing(ctx);
        let amount = 12345;

        // Create and register coin
        let (treasury_cap, coin_metadata) = create_test_coin(ctx);
        let mut coin_management = coin_management::new_with_cap(treasury_cap);
        coin_management.add_distributor(distributor_id.to_address());
        
        let deployer = channel::new(ctx);
        let salt = bytes32::from_address(@0x1234);
        let (token_id, treasury_cap_reclaimer) = its.register_custom_coin(
            &deployer,
            salt,
            &coin_metadata,
            coin_management,
            ctx,
        );

        let coin = mint<OPERATORS>(
            &mut its,
            &mut operators,
            &operator_cap,
            distributor_id,
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
        test_utils::destroy(operator_cap);
        test_utils::destroy(coin);
        test_utils::destroy(treasury_cap_reclaimer);
    }

    
}


