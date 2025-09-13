module gas_service::gas_service_v0 {
    use axelar_gateway::message_ticket::MessageTicket;
    use gas_service::events;
    use std::{ascii::String, type_name::{Self, TypeName}};
    use sui::{address, bag::{Self, Bag}, balance::{Self, Balance}, coin::{Self, Coin}, hash::keccak256};
    use version_control::version_control::VersionControl;

    // -------
    // Structs
    // -------
    public struct GasService_v0 has store {
        balances: Bag,
        version_control: VersionControl,
    }

    // -----------------
    // Package Functions
    // -----------------
    public(package) fun new(version_control: VersionControl, ctx: &mut TxContext): GasService_v0 {
        GasService_v0 {
            balances: bag::new(ctx),
            version_control,
        }
    }

    public(package) fun version_control(self: &GasService_v0): &VersionControl {
        &self.version_control
    }

    public(package) fun pay_gas<T>(
        self: &mut GasService_v0,
        message_ticket: &MessageTicket,
        coin: Coin<T>,
        refund_address: address,
        params: vector<u8>,
    ) {
        let coin_value = coin.value();
        self.put(coin);

        let payload_hash = address::from_bytes(
            keccak256(&message_ticket.payload()),
        );

        events::gas_paid<T>(
            message_ticket.source_id(),
            message_ticket.destination_chain(),
            message_ticket.destination_address(),
            payload_hash,
            coin_value,
            refund_address,
            params,
        );
    }

    public(package) fun add_gas<T>(
        self: &mut GasService_v0,
        coin: Coin<T>,
        message_id: String,
        refund_address: address,
        params: vector<u8>,
    ) {
        let coin_value = coin.value();
        self.put(coin);

        events::gas_added<T>(
            message_id,
            coin_value,
            refund_address,
            params,
        );
    }

    public(package) fun collect_gas<T>(self: &mut GasService_v0, receiver: address, amount: u64, ctx: &mut TxContext) {
        transfer::public_transfer(
            self.take<T>(amount, ctx),
            receiver,
        );

        events::gas_collected<T>(
            receiver,
            amount,
        );
    }

    public(package) fun refund<T>(self: &mut GasService_v0, message_id: String, receiver: address, amount: u64, ctx: &mut TxContext) {
        transfer::public_transfer(
            self.take<T>(amount, ctx),
            receiver,
        );

        events::refunded<T>(
            message_id,
            amount,
            receiver,
        );
    }

    public(package) fun allow_function(self: &mut GasService_v0, version: u64, function_name: String) {
        self.version_control.allow_function(version, function_name);
    }

    public(package) fun disallow_function(self: &mut GasService_v0, version: u64, function_name: String) {
        self.version_control.disallow_function(version, function_name);
    }

    public(package) fun balance<T>(self: &GasService_v0): &Balance<T> {
        self.balances.borrow<TypeName, Balance<T>>(type_name::with_defining_ids<T>())
    }

    // -----------------
    // Private Functions
    // -----------------
    fun put<T>(self: &mut GasService_v0, coin: Coin<T>) {
        coin::put(self.balance_mut<T>(), coin);
    }

    fun take<T>(self: &mut GasService_v0, amount: u64, ctx: &mut TxContext): Coin<T> {
        coin::take(self.balance_mut<T>(), amount, ctx)
    }

    fun balance_mut<T>(self: &mut GasService_v0): &mut Balance<T> {
        let key = type_name::with_defining_ids<T>();

        if (!self.balances.contains(key)) {
            self.balances.add(key, balance::zero<T>());
        };

        self.balances.borrow_mut<TypeName, Balance<T>>(key)
    }

    // ---------
    // Test Only
    // ---------
    #[test_only]
    public(package) fun version_control_mut(self: &mut GasService_v0): &mut VersionControl {
        &mut self.version_control
    }

    #[test_only]
    public(package) fun balance_mut_for_testing<T>(self: &mut GasService_v0): &mut Balance<T> {
        self.balance_mut<T>()
    }

    #[test_only]
    public(package) fun destroy_for_testing(self: GasService_v0) {
        let GasService_v0 { balances, version_control: _ } = self;
        sui::test_utils::destroy(balances);
    }
}
