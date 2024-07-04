module gas_service::gas_service {
    use std::ascii::String;

    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::address;
    use sui::hash::keccak256;
    use sui::event;

    // -----
    // Types
    // -----

    public struct GasService has key, store {
        id: UID,
        balance: Balance<SUI>,
    }

    public struct GasCollectorCap has key, store {
        id: UID,
    }

    // ------
    // Events
    // ------

    public struct GasPaid<phantom T> has copy, drop {
        sender: address,
        destination_chain: String,
        destination_address: String,
        payload_hash: address,
        value: u64,
        refund_address: address,
        params: vector<u8>,
    }

    public struct GasAdded<phantom T> has copy, drop {
        message_id: String,
        value: u64,
        refund_address: address,
        params: vector<u8>,
    }

    public struct Refunded<phantom T> has copy, drop {
        message_id: String,
        value: u64,
        refund_address: address,
    }

    public struct GasCollected<phantom T> has copy, drop {
        receiver: address,
        value: u64,
    }

    // -----
    // Setup
    // -----

    fun init(ctx: &mut TxContext) {
        transfer::share_object(GasService {
            id: object::new(ctx),
            balance: balance::zero<SUI>(),
        });

        transfer::public_transfer(GasCollectorCap {
            id: object::new(ctx),
        }, ctx.sender());
    }

    // ----------------
    // Public Functions
    // ----------------

    /// Pay gas for a contract call.
    /// This function is called by the channel that wants to pay gas for a contract call.
    /// It can also be called by the user to pay gas for a contract call, while setting the sender as the channel ID.
    public fun pay_gas(
        self: &mut GasService,
        coin: Coin<SUI>,
        sender: address,
        destination_chain: String,
        destination_address: String,
        payload: vector<u8>,
        refund_address: address,
        params: vector<u8>,
    ) {
        let value = coin.value();
        coin::put(&mut self.balance, coin);
        let payload_hash = address::from_bytes(keccak256(&payload));

        event::emit(GasPaid<SUI> {
            sender,
            destination_chain,
            destination_address,
            payload_hash,
            value,
            refund_address,
            params,
        })
    }

    /// Add gas for an existing cross-chain contract call.
    /// This function can be called by a user who wants to add gas for a contract call with insufficient gas.
    public fun add_gas(
        self: &mut GasService,
        coin: Coin<SUI>,
        message_id: String,
        refund_address: address,
        params: vector<u8>,
    ) {
        let value = coin.value();
        coin::put(&mut self.balance, coin);

        event::emit(GasAdded<SUI> {
            message_id,
            value,
            refund_address,
            params,
        });
    }

    public fun collect_gas(self: &mut GasService, _: &GasCollectorCap, receiver: address, amount: u64, ctx: &mut TxContext) {
        transfer::public_transfer(
            coin::take(&mut self.balance, amount, ctx),
            receiver,
        );

        event::emit(GasCollected<SUI> {
            receiver,
            value: amount,
        });
    }

    public fun refund(self: &mut GasService, _: &GasCollectorCap, message_id: String, receiver: address, amount: u64, ctx: &mut TxContext) {
        transfer::public_transfer(
            coin::take(&mut self.balance, amount, ctx),
            receiver,
        );

        event::emit(Refunded<SUI> {
            message_id,
            value: amount,
            refund_address: receiver,
        });
    }

    // -----
    // Tests
    // -----

    #[test_only]
    fun new(ctx: &mut TxContext): (GasService, GasCollectorCap) {
        let service = GasService {
            id: object::new(ctx),
            balance: balance::zero<SUI>(),
        };

        let cap = GasCollectorCap {
            id: object::new(ctx),
        };

        (service, cap)
    }

    #[test_only]
    fun destroy(self: GasService) {
        let GasService { id, balance } = self;
        id.delete();
        balance.destroy_for_testing();
    }

    #[test_only]
    fun destroy_cap(self: GasCollectorCap) {
        let GasCollectorCap { id } = self;
        id.delete();
    }

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

        service.pay_gas(
            c,
            ctx.sender(),
            std::ascii::string(b"destination chain"),
            std::ascii::string(b"destination address"),
            vector[],
            ctx.sender(),
            vector[],
        );

        assert!(service.balance.value() == value, 0);

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    fun test_add_gas() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) + 1; // 1..65,536
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        assert!(service.balance.value() == value, 0);

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    fun test_collect_gas() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) + 1; // 1..65,536
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        service.collect_gas(
            &cap,
            ctx.sender(),
            value,
            ctx,
        );

        assert!(service.balance.value() == 0, 0);

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    fun test_refund() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) + 1; // 1..65,536
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        service.refund(
            &cap,
            std::ascii::string(b"message id"),
            ctx.sender(),
            value,
            ctx,
        );

        assert!(service.balance.value() == 0, 0);

        cap.destroy_cap();
        service.destroy();
    }

    #[test]
    #[expected_failure(abort_code = sui::balance::ENotEnough)]
    fun test_collect_gas_insufficient_balance() {
        let ctx = &mut sui::tx_context::dummy();
        let (mut service, cap) = new(ctx);
        let digest = ctx.digest();
        let value = (((digest[0] as u16) << 8) | (digest[1] as u16) as u64) + 1; // 1..65,536
        let c: Coin<SUI> = coin::mint_for_testing(value, ctx);

        service.add_gas(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        service.collect_gas(
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

        service.add_gas(
            c,
            std::ascii::string(b"message id"),
            @0x0,
            vector[],
        );

        service.refund(
            &cap,
            std::ascii::string(b"message id"),
            ctx.sender(),
            value + 1,
            ctx,
        );

        cap.destroy_cap();
        service.destroy();
    }
}
