module interchain_token_service::coin_management {
    use axelar_gateway::channel::Channel;
    use interchain_token_service::flow_limit::{Self, FlowLimit};
    use sui::{balance::{Self, Balance}, clock::Clock, coin::{Self, TreasuryCap, Coin}};

    // ------
    // Errors
    // ------
    #[error]
    const EDistributorNeedsTreasuryCap: vector<u8> =
        b"trying to add a distributor to a `CoinManagement` that does not have a `TreasuryCap`";
    #[error]
    const ENotOperator: vector<u8> = b"channel provided is not the operator";
    #[error]
    const ENoTreasuryCapPresent: vector<u8> = b"trying to remove a treasury cap that does not exist";
    #[error]
    const ENotMintBurn: vector<u8> = b"trying to add a treasury cap to a lock unlock token";
    #[error]
    const ETreasuryCapRemovedFromMintBurnToken: vector<u8> = b"treasury cap for mint/burn token was removed";

    /// Struct that stores information about the InterchainTokenService Coin.
    public struct CoinManagement<phantom T> has store {
        treasury_cap: Option<TreasuryCap<T>>,
        balance: Option<Balance<T>>,
        distributor: Option<address>,
        operator: Option<address>,
        flow_limit: FlowLimit,
        dust: u256,
    }

    // ------
    // Public Functions to create CoinManagement
    // ------
    /// Create a new `CoinManagement` with a `TreasuryCap`.
    /// This type of `CoinManagement` allows minting and burning of coins.
    public fun new_with_cap<T>(treasury_cap: TreasuryCap<T>): CoinManagement<T> {
        CoinManagement<T> {
            treasury_cap: option::some(treasury_cap),
            balance: option::none(),
            distributor: option::none(),
            operator: option::none(),
            flow_limit: flow_limit::new(),
            dust: 0,
        }
    }

    /// Create a new `CoinManagement` with a `Balance`.
    /// The stored `Balance` can be used to take and put coins.
    public fun new_locked<T>(): CoinManagement<T> {
        CoinManagement<T> {
            treasury_cap: option::none(),
            balance: option::some(balance::zero()),
            distributor: option::none(),
            operator: option::none(),
            flow_limit: flow_limit::new(),
            dust: 0,
        }
    }

    // ------
    // Functions that modify CoinManagement
    // ------
    /// Adds the distributor address to the `CoinManagement`.
    /// Only works for a `CoinManagement` with a `TreasuryCap`.
    public fun add_distributor<T>(self: &mut CoinManagement<T>, distributor: address) {
        assert!(self.has_treasury_cap(), EDistributorNeedsTreasuryCap);
        self.distributor.fill(distributor);
    }

    /// Adds the distributor address to the `CoinManagement`.
    /// Only works for a `CoinManagement` with a `TreasuryCap`.
    public fun add_operator<T>(self: &mut CoinManagement<T>, operator: address) {
        self.operator.fill(operator);
    }

    // -------
    // Getters
    // -------
    public fun operator<T>(self: &CoinManagement<T>): &Option<address> {
        &self.operator
    }

    public fun distributor<T>(self: &CoinManagement<T>): &Option<address> {
        &self.distributor
    }

    /// Returns true if the coin management has a `TreasuryCap`.
    public fun has_treasury_cap<T>(self: &CoinManagement<T>): bool {
        self.treasury_cap.is_some()
    }

    public fun treasury_cap<T>(self: &CoinManagement<T>): &Option<TreasuryCap<T>> {
        &self.treasury_cap
    }

    // === Protected Methods ===

    /// Takes the given amount of Coins from user. Returns the amount that the InterchainTokenService
    /// is supposed to give on other chains.
    public(package) fun take_balance<T>(self: &mut CoinManagement<T>, to_take: Balance<T>, clock: &Clock): u64 {
        self.flow_limit.add_flow_out(to_take.value(), clock);
        let amount = to_take.value();
        if (self.has_treasury_cap()) {
            self.burn(to_take);
        } else {
            assert!(self.balance.is_some(), ETreasuryCapRemovedFromMintBurnToken);
            self.balance.borrow_mut().join(to_take);
        };
        amount
    }

    /// Withdraws or mints the given amount of coins. Any leftover amount from
    /// previous transfers is added to the coin here.
    public(package) fun give_coin<T>(self: &mut CoinManagement<T>, amount: u64, clock: &Clock, ctx: &mut TxContext): Coin<T> {
        self.flow_limit.add_flow_in(amount, clock);
        if (self.has_treasury_cap()) {
            self.mint(amount, ctx)
        } else {
            assert!(self.balance.is_some(), ETreasuryCapRemovedFromMintBurnToken);
            coin::take(self.balance.borrow_mut(), amount, ctx)
        }
    }

    // helper function to mint as a distributor.
    public(package) fun mint<T>(self: &mut CoinManagement<T>, amount: u64, ctx: &mut TxContext): Coin<T> {
        self.treasury_cap.borrow_mut().mint(amount, ctx)
    }

    // helper function to burn as a distributor.
    public(package) fun burn<T>(self: &mut CoinManagement<T>, balance: Balance<T>) {
        self.treasury_cap.borrow_mut().supply_mut().decrease_supply(balance);
    }

    /// Adds a rate limit to the `CoinManagement`.
    public(package) fun set_flow_limit<T>(self: &mut CoinManagement<T>, channel: &Channel, flow_limit: Option<u64>) {
        assert!(self.operator.contains(&channel.to_address()), ENotOperator);
        self.set_flow_limit_internal(flow_limit);
    }

    /// Adds a rate limit to the `CoinManagement`.
    public(package) fun set_flow_limit_internal<T>(self: &mut CoinManagement<T>, flow_limit: Option<u64>) {
        self.flow_limit.set_flow_limit(flow_limit);
    }

    public(package) fun update_distributorship<T>(self: &mut CoinManagement<T>, new_distributor: Option<address>) {
        self.distributor = new_distributor;
    }

    public(package) fun update_operatorship<T>(self: &mut CoinManagement<T>, channel: &Channel, new_operator: Option<address>) {
        assert!(self.operator.contains(&channel.to_address()), ENotOperator);
        self.operator = new_operator;
    }

    public(package) fun remove_cap<T>(self: &mut CoinManagement<T>): TreasuryCap<T> {
        assert!(self.has_treasury_cap(), ENoTreasuryCapPresent);

        self.treasury_cap.extract()
    }

    public(package) fun restore_cap<T>(self: &mut CoinManagement<T>, treasury_cap: TreasuryCap<T>) {
        assert!(self.balance.is_none(), ENotMintBurn);

        self.treasury_cap.fill(treasury_cap);
    }

    public(package) fun destroy<T>(self: CoinManagement<T>): (Option<TreasuryCap<T>>, Option<Balance<T>>) {
        let CoinManagement {
            treasury_cap,
            balance,
            distributor: _,
            operator: _,
            flow_limit: _,
            dust: _,
        } = self;

        (treasury_cap, balance)
    }

    // === Views ===

    /// Checks if the given address is a `distributor`.
    public fun is_distributor<T>(self: &CoinManagement<T>, distributor: address): bool {
        &distributor == self.distributor.borrow()
    }

    // === Tests ===
    #[test_only]
    public struct COIN_MANAGEMENT has drop {}

    #[test_only]
    fun create_currency(): (TreasuryCap<COIN_MANAGEMENT>, sui::coin::CoinMetadata<COIN_MANAGEMENT>) {
        sui::coin::create_currency<COIN_MANAGEMENT>(
        sui::test_utils::create_one_time_witness<COIN_MANAGEMENT>(),
        6,
        b"TT",
        b"Test Token",
        b"",
        option::none<sui::url::Url>(),
        &mut sui::tx_context::dummy(),
    )
    }
    #[test]
    fun test_take_balance() {
        let (mut cap, metadata) = create_currency();
        let ctx = &mut sui::tx_context::dummy();
        let amount1 = 10;
        let amount2 = 20;

        let mut coin = cap.mint(amount1, ctx);
        let mut management1 = new_locked<COIN_MANAGEMENT>();
        let clock = sui::clock::create_for_testing(ctx);
        management1.take_balance(coin.into_balance(), &clock);

        assert!(management1.balance.borrow().value() == amount1);

        coin = cap.mint(amount2, ctx);
        let mut management2 = new_with_cap<COIN_MANAGEMENT>(cap);
        management2.take_balance(coin.into_balance(), &clock);

        sui::test_utils::destroy(metadata);
        sui::test_utils::destroy(management1);
        sui::test_utils::destroy(management2);
        sui::test_utils::destroy(clock);
    }

    #[test]
    fun test_give_coin() {
        let (mut cap, metadata) = create_currency();
        let ctx = &mut sui::tx_context::dummy();
        let amount1 = 10;
        let amount2 = 20;

        let mut coin = cap.mint(amount1, ctx);
        let mut management1 = new_locked<COIN_MANAGEMENT>();
        let clock = sui::clock::create_for_testing(ctx);
        management1.take_balance(coin.into_balance(), &clock);
        coin = management1.give_coin(amount1, &clock, ctx);

        assert!(management1.balance.borrow().value() == 0);
        assert!(coin.value() == amount1);

        sui::test_utils::destroy(coin);

        let mut management2 = new_with_cap<COIN_MANAGEMENT>(cap);
        coin = management2.give_coin(amount2, &clock, ctx);

        assert!(coin.value() == amount2);

        sui::test_utils::destroy(coin);
        sui::test_utils::destroy(metadata);
        sui::test_utils::destroy(management1);
        sui::test_utils::destroy(management2);
        sui::test_utils::destroy(clock);
    }

    #[test]
    #[expected_failure(abort_code = EDistributorNeedsTreasuryCap)]
    fun test_add_distributor_no_capability() {
        let mut management = new_locked<COIN_MANAGEMENT>();
        let distributor = @0x1;

        management.add_distributor(distributor);

        sui::test_utils::destroy(management);
    }

    #[test]
    fun test_add_operator() {
        let mut management = new_locked<COIN_MANAGEMENT>();
        let operator = @0x1;

        management.add_operator(operator);

        sui::test_utils::destroy(management);
    }

    #[test]
    fun test_set_flow_limit() {
        let ctx = &mut sui::tx_context::dummy();

        let mut management = new_locked<COIN_MANAGEMENT>();
        let channel = axelar_gateway::channel::new(ctx);

        management.add_operator(channel.to_address());
        management.set_flow_limit(&channel, option::some(1));

        sui::test_utils::destroy(management);
        sui::test_utils::destroy(channel);
    }

    #[test]
    #[expected_failure(abort_code = ENotOperator)]
    fun test_set_flow_limit_not_operator() {
        let ctx = &mut sui::tx_context::dummy();

        let mut management = new_locked<COIN_MANAGEMENT>();
        let channel = axelar_gateway::channel::new(ctx);
        let operator = @0x1;

        management.add_operator(operator);
        management.set_flow_limit(&channel, option::some(1));

        sui::test_utils::destroy(management);
        sui::test_utils::destroy(channel);
    }

    #[test]
    #[expected_failure(abort_code = ENotMintBurn)]
    fun test_add_cap_not_mint_burn() {
        let ctx = &mut sui::tx_context::dummy();

        let treasury_cap = interchain_token_service::coin::create_treasury(b"symbol", 9, ctx);

        let mut coin_management = new_locked();

        coin_management.restore_cap(treasury_cap);

        sui::test_utils::destroy(coin_management);
    }

    #[test]
    fun test_treasury_cap() {
        let (treasury_cap, metadata) = create_currency();
        let coin_management = new_with_cap<COIN_MANAGEMENT>(treasury_cap);

        treasury_cap<COIN_MANAGEMENT>(&coin_management);

        sui::test_utils::destroy(metadata);
        sui::test_utils::destroy(coin_management);
    }
}
