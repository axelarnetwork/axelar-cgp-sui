module gas_service::gas_service {
    use std::ascii::String;

    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::address;
    use sui::hash::keccak256;
    use sui::event;

    public struct GasService
     has key, store {
        id: UID,
        balance: Balance<SUI>,
    }

    public struct RefunderCap has key, store {
        id: UID,
    }

    public struct NativeGasPaidForContractCall has copy, drop {
        sender: address, 
        destination_chain: String, 
        destination_address: String, 
        payload_hash: address, 
        value: u64,
        refund_address: address,
    }

    public struct NativeGasAdded has copy, drop {
        tx_hash: address, 
        log_index: u64,
        value: u64, 
        refund_address: address,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(GasService {
            id: object::new(ctx),
            balance: balance::zero<SUI>(),
        });

        transfer::public_transfer(RefunderCap {
            id: object::new(ctx),
        }, ctx.sender());
    }

    // This can only be called once since it needs its own upgrade cap which it deletes.
    public fun pay_native_gas_for_contract_call(
        self: &mut GasService,
        coin: Coin<SUI>,
        sender: address,
        destination_chain: String,
        destination_address: String,
        payload: vector<u8>,
        refund_address: address,
    ) {
        let value = coin.value();
        coin::put(&mut self.balance, coin);
        let payload_hash = address::from_bytes(keccak256(&payload));
        event::emit( NativeGasPaidForContractCall {
            sender,
            destination_chain,
            destination_address,
            payload_hash,
            value,
            refund_address,
        })
    }

    public fun add_native_gas(
        self: &mut GasService,
        coin: Coin<SUI>,
        tx_hash: address,
        log_index: u64,
        refund_address: address
    ) {
        let value = coin.value();
        coin::put(&mut self.balance, coin);
        event::emit( NativeGasAdded {
            tx_hash,
            log_index,
            value,
            refund_address,
        });
    }

    public fun refund(self: &mut GasService, _: &RefunderCap, receiver: address, amount: u64, ctx: &mut TxContext) {
        transfer::public_transfer(
            coin::take(&mut self.balance, amount, ctx),
            receiver,
        )
    }
}