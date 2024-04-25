module squid::coin_bag {    
    use std::type_name::{Self};

    use sui::bag::{Self, Bag};
    use sui::balance::{Balance};
    use sui::hash::keccak256;
    use sui::address;

    public struct CoinBag has store {
        bag: Bag,
    }

    public(package) fun new(ctx: &mut TxContext): CoinBag {
        CoinBag{
            bag: bag::new(ctx),
        }
    }

    public(package) fun store_balance<T>(self: &mut CoinBag, balance: Balance<T>) {
        let key = get_balance_key<T>();
        
        if(self.bag.contains(key)) {
            self.bag.borrow_mut<address, Balance<T>>(key).join(
                balance,
            );
        } else {
            self.bag.add(
                key,
                balance,
            )
        }
    }

    public(package) fun get_balance<T>(self: &mut CoinBag): Option<Balance<T>> {
        let key = get_balance_key<T>();
        
        if(self.bag.contains(key)) {
            option::some(self.bag.remove<address, Balance<T>>(key))
        } else {
            option::none<Balance<T>>()
        }
    }


    public(package) fun get_balance_amount<T>(self: &CoinBag): u64 {
        let key = get_balance_key<T>();
        
        if(self.bag.contains(key)) {
            self.bag.borrow<address, Balance<T>>(key).value()
        } else {
            0
        }
    }


    public(package) fun store_estimate<T>(self: &mut CoinBag, estimate: u64) {
        let key = get_estimate_key<T>();
        
        if(self.bag.contains(key)) {
            let previous = self.bag.borrow_mut<address, u64>(key);
            *previous = *previous + estimate;
        } else {
            self.bag.add(
                key,
                estimate,
            )
        }
    }

    public(package) fun get_estimate<T>(self: &mut CoinBag): u64 {
        let key = get_estimate_key<T>();
        
        if(self.bag.contains(key)) {
            self.bag.remove<address, u64>(key)
        } else {
            0
        }
    }

    public(package) fun get_estimate_amount<T>(self: &CoinBag): u64 {
        let key = get_estimate_key<T>();
        
        if(self.bag.contains(key)) {
            *self.bag.borrow<address, u64>(key)
        } else {
            0
        }
    }

    public(package) fun destroy(self: CoinBag) {
        let CoinBag { bag } = self;
        bag.destroy_empty();
    }


    fun get_balance_key<T>(): address {
        let mut data = vector[0];
        vector::append(&mut data, type_name::get<T>().into_string().into_bytes());
        address::from_bytes(keccak256(&data))
    }

    fun get_estimate_key<T>(): address {
        let mut data = vector[1];
        vector::append(&mut data, type_name::get<T>().into_string().into_bytes());
        address::from_bytes(keccak256(&data))
    }
}