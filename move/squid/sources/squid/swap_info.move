module squid::swap_info {
    use std::ascii::{Self, String};
    use std::type_name;

    use sui::bcs;
    use sui::balance::Balance;
    use sui::coin;

    use its::service;
    use its::its::ITS;
    use its::token_id;

    use squid::coin_bag::{Self, CoinBag};

    public struct SwapInfo {
        swap_index: u64,
        estimate_index: u64,
        swap_data: vector<vector<u8>>,
        coin_bag: CoinBag,
        type_in: String,
        amount_in: u64,
        destination_in: vector<u8>,
        type_out: String,
        min_out: u64,
        destination_out: vector<u8>,
        status: u8,
    }

    const ESTIMATING: u8 = 0;
    const SWAPPING: u8 = 1;
    const SKIP_SWAP: u8 = 2;

    const EOutOfEstimates: u64 = 0;
    const EOutOfSwaps: u64 = 1;
    const EWrongTypeOut: u64 = 2;
    const ENotEstimating: u64 = 3;
    const ENotSwapping: u64 = 4;
    const ENotDoneEstimating: u64 = 5;
    const ENotDoneSwapping: u64 = 6;
    const ENotEnoughOutput: u64 = 7;
    const EIncorrectInput: u64 = 8;

    public(package) fun decode_swap_info_data(data: vector<u8>): (vector<vector<u8>>, String, u64, vector<u8>, String, u64, vector<u8>) {
        let mut bcs = bcs::new(data);
        
        let swap_data = bcs.peel_vec_vec_u8();
        let type_in = ascii::string(bcs.peel_vec_u8());
        let amount_in = bcs.peel_u64();
        let destination_in = bcs.peel_vec_u8();
        let type_out = ascii::string(bcs.peel_vec_u8());
        let min_out = bcs.peel_u64();
        let destination_out = bcs.peel_vec_u8();

        (swap_data, type_in, amount_in, destination_in, type_out, min_out, destination_out)
    }


    public(package) fun new(data: vector<u8>, ctx: &mut TxContext): SwapInfo {
        let (swap_data, type_in, amount_in, destination_in, type_out, min_out, destination_out) = decode_swap_info_data(data);
        SwapInfo {
            swap_index: 0,
            estimate_index: 0,
            status: ESTIMATING,
            coin_bag: coin_bag::new(ctx),

            swap_data,
            type_in,
            amount_in,
            destination_in,
            type_out,
            min_out,
            destination_out,
        }
    }

    public(package) fun get_data_swapping(self: &mut SwapInfo): vector<u8> {
        if(self.status == SKIP_SWAP) {
            return vector[]
        };

        assert!(self.status == SWAPPING, ENotSwapping);

        let index = self.swap_index;
        assert!(index < vector::length(&self.swap_data), EOutOfSwaps);

        self.swap_index = index + 1;

        *vector::borrow(&self.swap_data, index)
    }

    public(package) fun get_data_estimating(self: &mut SwapInfo): vector<u8> {
        assert!(self.status == ESTIMATING, ENotEstimating);

        let index = self.estimate_index;
        assert!(index < vector::length(&self.swap_data), EOutOfEstimates);

        self.estimate_index = index + 1;
        
        *vector::borrow(&self.swap_data, index)
    }

    public(package) fun coin_bag(self: &mut SwapInfo): &mut CoinBag {
        &mut self.coin_bag
    }
    public(package) fun swap_data(self: &SwapInfo, i: u64): vector<u8> {
        *vector::borrow(&self.swap_data, i)
    }

    public fun post_estimate<T>(self: &mut SwapInfo) {
        assert!(&self.type_out == type_name::get<T>().into_string(), EWrongTypeOut);

        assert!(self.status == ESTIMATING, ENotEstimating);
        assert!(self.estimate_index == vector::length(&self.swap_data), ENotDoneEstimating);
        if(self.min_out >= self.coin_bag.get_estimate<T>()) {
            self.status = SWAPPING;
        } else {
            self.status = SKIP_SWAP;
        }
    }


    public(package) fun done_and_successfull(self: &SwapInfo): bool {
        assert!(
            (
                self.status == SWAPPING && 
                self.swap_index == vector::length(&self.swap_data)
            ) || 
            self.status == SKIP_SWAP, ENotDoneSwapping
        );

        self.status == SWAPPING
    }

    public fun finalize<T1, T2>(mut self: SwapInfo, its: &mut ITS, ctx: &mut TxContext) {
        let successfull = self.done_and_successfull();

        assert!(&self.type_in == type_name::get<T1>().into_string(), EWrongTypeOut);
        assert!(&self.type_out == type_name::get<T2>().into_string(), EWrongTypeOut);

        if (successfull) {
            let balance = self.coin_bag.get_balance<T2>().destroy_some();
            assert!(balance.value() >= self.min_out, ENotEnoughOutput);
            send_balance(balance, self.destination_out, its, ctx);
        } else {
            let balance = self.coin_bag.get_balance<T1>().destroy_some();
            assert!(balance.value() == self.amount_in, EIncorrectInput);
            send_balance(balance, self.destination_in, its, ctx);
        };
        self.destroy();
    }

    fun destroy(self: SwapInfo) {
        let SwapInfo { 
            swap_index: _,
            estimate_index: _,
            swap_data: _,
            coin_bag,
            type_in: _,
            amount_in: _,
            destination_in: _,
            type_out: _,
            min_out: _,
            destination_out: _,
            status: _,
        } = self;
        coin_bag.destroy();
    }

    fun send_balance<T>(balance: Balance<T>, destination: vector<u8>, its: &mut ITS, ctx: &mut TxContext) {
        let coin = coin::from_balance(balance, ctx);

        let mut bcs = bcs::new(destination);
        let to_sui = bcs.peel_bool();
        if(to_sui) {
            let address = bcs.peel_address();
            transfer::public_transfer(coin, address);
        } else {
            let token_id = token_id::from_address(bcs.peel_address());
            let destination_chain = ascii::string(bcs.peel_vec_u8());
            let destination_address = bcs.peel_vec_u8();
            let metadata = bcs.peel_vec_u8();
            service::interchain_transfer(
                its,
                token_id,
                coin,
                destination_chain,
                destination_address,
                metadata,
                ctx,
            );
        }
    }
}