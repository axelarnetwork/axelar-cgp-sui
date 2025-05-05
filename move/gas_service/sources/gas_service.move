module gas_service::gas_service {
    use axelar_gateway::message_ticket::MessageTicket;
    use gas_service::{gas_service_v0::{Self, GasService_v0}, operator_cap::{Self, OperatorCap}, owner_cap::{Self, OwnerCap}};
    use std::ascii::{Self, String};
    use sui::{balance::Balance, coin::Coin, hash::keccak256, versioned::{Self, Versioned}};
    use version_control::version_control::{Self, VersionControl};

    // -------
    // Version
    // -------
    const VERSION: u64 = 0;

    // -------
    // Structs
    // -------
    public struct GasService has key, store {
        id: UID,
        inner: Versioned,
    }

    // -----
    // Setup
    // -----
    fun init(ctx: &mut TxContext) {
        transfer::share_object(GasService {
            id: object::new(ctx),
            inner: versioned::create(
                VERSION,
                gas_service_v0::new(
                    version_control(),
                    ctx,
                ),
                ctx,
            ),
        });

        transfer::public_transfer(
            operator_cap::create(ctx),
            ctx.sender(),
        );

        transfer::public_transfer(
            owner_cap::create(ctx),
            ctx.sender(),
        );
    }

    // ------
    // Macros
    // ------
    macro fun value_mut($self: &GasService, $function_name: vector<u8>): &mut GasService_v0 {
        let gas_service = $self;
        let value = gas_service.inner.load_value_mut<GasService_v0>();
        value.version_control().check(VERSION, ascii::string($function_name));
        value
    }

    // We do not need to check version control for getters.
    macro fun value($self: &GasService): &GasService_v0 {
        let gas_service = $self;
        gas_service.inner.load_value<GasService_v0>()
    }

    // ---------------
    // Entry Functions
    // ---------------
    entry fun allow_function(self: &mut GasService, _: &OwnerCap, version: u64, function_name: String) {
        self.value_mut!(b"allow_function").allow_function(version, function_name);
    }

    entry fun disallow_function(self: &mut GasService, _: &OwnerCap, version: u64, function_name: String) {
        self.value_mut!(b"disallow_function").disallow_function(version, function_name);
    }

    // ----------------
    // Public Functions
    // ----------------
    /// Pay gas for a contract call.
    /// This function is called by the channel that wants to pay gas for a contract
    /// call.
    /// It can also be called by the user to pay gas for a contract call, while
    /// setting the sender as the channel ID.
    public fun pay_gas<T>(
        self: &mut GasService,
        message_ticket: &MessageTicket,
        coin: Coin<T>,
        refund_address: address,
        params: vector<u8>,
    ) {
        self
            .value_mut!(b"pay_gas")
            .pay_gas<T>(
                message_ticket,
                coin,
                refund_address,
                params,
            );
    }

    /// Add gas for an existing cross-chain contract call.
    /// This function can be called by a user who wants to add gas for a contract
    /// call with insufficient gas.
    public fun add_gas<T>(self: &mut GasService, coin: Coin<T>, message_id: String, refund_address: address, params: vector<u8>) {
        self
            .value_mut!(b"add_gas")
            .add_gas<T>(
                coin,
                message_id,
                refund_address,
                params,
            );
    }

    public fun collect_gas<T>(self: &mut GasService, _: &OperatorCap, receiver: address, amount: u64, ctx: &mut TxContext) {
        self
            .value_mut!(b"collect_gas")
            .collect_gas<T>(
                receiver,
                amount,
                ctx,
            )
    }

    public fun refund<T>(self: &mut GasService, _: &OperatorCap, message_id: String, receiver: address, amount: u64, ctx: &mut TxContext) {
        self
            .value_mut!(b"refund")
            .refund<T>(
                message_id,
                receiver,
                amount,
                ctx,
            );
    }

    public fun balance<T>(self: &GasService): &Balance<T> {
        self.value!().balance<T>()
    }

    // -----------------
    // Private Functions
    // -----------------
    fun version_control(): VersionControl {
        version_control::new(vector[
            vector[b"pay_gas", b"add_gas", b"collect_gas", b"refund", b"allow_function", b"disallow_function"].map!(
                |function_name| function_name.to_ascii_string(),
            ),
        ])
    }

    // -----
    // Tests
    // -----
    #[test_only]
    use sui::{coin, sui::SUI};

    #[test_only]
    fun new(ctx: &mut TxContext): (GasService, OperatorCap) {
        let service = GasService {
            id: object::new(ctx),
            inner: versioned::create(
                VERSION,
                gas_service_v0::new(
                    version_control(),
                    ctx,
                ),
                ctx,
            ),
        };

        let cap = operator_cap::create(ctx);

        (service, cap)
    }

    #[test_only]
    fun destroy(self: GasService) {
        let GasService { id, inner } = self;
        id.delete();
        let data = inner.destroy<GasService_v0>();
        data.destroy_for_testing();
    }

    /// -----
    /// Tests
    /// -----
    #[test]
    fun test_init() {
        let ctx = &mut sui::tx_context::dummy();
        init(ctx);
    }

    #[test]
    fun test_pay_gas() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        // 2 bytes of the digest for a pseudo-random 1..65,536
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) + 1;
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);
        let channel = axelar_gateway::channel::new(ctx);
        let destination_chain = b"destination chain".to_ascii_string();
        let destination_address = b"destination address".to_ascii_string();
        let payload = b"payload";

        let ticket = axelar_gateway::gateway::prepare_message(
            &channel,
            destination_chain,
            destination_address,
            payload,
        );

        service.pay_gas(
            &ticket,
            c,
            ctx.sender(),
            vector[],
        );

        assert!(service.value!().balance<SUI>().value() == value);

        cap.destroy_cap();
        service.destroy();
        channel.destroy();
        sui::test_utils::destroy(ticket);
    }

    #[test]
    fun test_add_gas() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) +
    1; // 1..65,536
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        assert!(service.value!().balance<SUI>().value() == value);

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    fun test_collect_gas() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) +
    1; // 1..65,536
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        service.collect_gas<SUI>(
            &cap,
            ctx.sender(),
            value,
            ctx,
        );

        assert!(service.value!().balance<SUI>().value() == 0);

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    fun test_refund() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) +
    1; // 1..65,536
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas<SUI>(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        service.refund<SUI>(
            &cap,
            std::ascii::string(b"message id"),
            ctx.sender(),
            value,
            ctx,
        );

        assert!(service.value!().balance<SUI>().value() == 0);

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    #[expected_failure(abort_code = sui::balance::ENotEnough)]
    fun test_collect_gas_insufficient_balance() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) +
    1; // 1..65,536
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        service.collect_gas<SUI>(
            &cap,
            ctx.sender(),
            value + 1,
            ctx,
        );

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    #[expected_failure(abort_code = sui::balance::ENotEnough)]
    fun test_refund_insufficient_balance() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let value = 10;
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas<SUI>(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        service.refund<SUI>(
            &cap,
            std::ascii::string(b"message id"),
            ctx.sender(),
            value + 1,
            ctx,
        );

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    fun test_allow_function() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut self, operator_cap) = new(ctx);
        let version = 0;
        let function_name = b"function_name".to_ascii_string();
        let cap = owner_cap::create(ctx);
        self.allow_function(&cap, version, function_name);

        sui::test_utils::destroy(self);
        operator_cap.destroy_cap();
        cap.destroy_cap();
    }

    #[test]
    fun test_disallow_function() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut self, operator_cap) = new(ctx);
        let version = 0;
        let function_name = b"pay_gas".to_ascii_string();

        let cap = owner_cap::create(ctx);
        self.disallow_function(&cap, version, function_name);

        sui::test_utils::destroy(self);
        operator_cap.destroy_cap();
        cap.destroy_cap();
    }
}
