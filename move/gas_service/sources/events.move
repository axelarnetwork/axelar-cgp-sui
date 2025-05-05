module gas_service::events {
    use std::ascii::String;
    use sui::event;

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

    // Package Functions
    public(package) fun gas_paid<T>(
        sender: address,
        destination_chain: String,
        destination_address: String,
        payload_hash: address,
        value: u64,
        refund_address: address,
        params: vector<u8>,
    ) {
        event::emit(GasPaid<T> {
            sender,
            destination_chain,
            destination_address,
            payload_hash,
            value,
            refund_address,
            params,
        });
    }

    public(package) fun gas_added<T>(message_id: String, value: u64, refund_address: address, params: vector<u8>) {
        event::emit(GasAdded<T> {
            message_id,
            value,
            refund_address,
            params,
        });
    }

    public(package) fun refunded<T>(message_id: String, value: u64, refund_address: address) {
        event::emit(Refunded<T> {
            message_id,
            value,
            refund_address,
        });
    }

    public(package) fun gas_collected<T>(receiver: address, value: u64) {
        event::emit(GasCollected<T> {
            receiver,
            value,
        });
    }
}
