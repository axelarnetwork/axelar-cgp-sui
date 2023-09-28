

module dummy_its::its_utils {
    use std::ascii;
    use std::vector;

    use sui::hash::{keccak256};
    use sui::address;

    const LOWERCASE_START: u8 = 97;
    const UPPERCASE_START: u8 = 65;
    const NUMBERS_START: u8 = 48;
    const SPACE: u8 = 32;
    const UNDERSCORE: u8 = 95;

    public fun convert_value(val: u256): u64 {
        (val as u64)
    }

    public fun isLowercase(c: u8): bool {
        c >= LOWERCASE_START && c <= LOWERCASE_START + 25
    }
    public fun isUppercase(c: u8): bool {
        c >= UPPERCASE_START && c <= UPPERCASE_START + 25
    }
    public fun isNumber(c: u8): bool {
        c >= NUMBERS_START && c <= NUMBERS_START + 9
    }

    public fun get_module_from_symbol(symbol: &ascii::String): ascii::String {
        let symbolBytes = ascii::as_bytes(symbol);
        let moduleName = vector[];

        let (i, length) = (0, vector::length(symbolBytes));
        if(isNumber(*vector::borrow(symbolBytes, 0))) vector::push_back(&mut moduleName, UNDERSCORE);
        while( i < length) {
            let b = *vector::borrow(symbolBytes, i);
            if( isLowercase(b) || isNumber(b) ) {
                vector::push_back(&mut moduleName, b);
            } else if( isUppercase(b) ) {
                vector::push_back(&mut moduleName, b - UPPERCASE_START + LOWERCASE_START);
            } else if(b == UNDERSCORE || b == SPACE) {
                vector::push_back(&mut moduleName, UNDERSCORE);
            };
            
            i = i + 1;
        };
        ascii::string(moduleName)
    }

    public fun hash_coin_info(symbol: &ascii::String, decimals: &u8): address {
        let v = vector::singleton(*decimals);
        vector::append<u8>(&mut v, *ascii::as_bytes(symbol));
        address::from_bytes(keccak256(&v))
    }

    #[test]
    fun test_get_module_from_symbol() {
        let symbol = ascii::string(b"1(TheCool1234Coin) _ []!");
        std::debug::print(&get_module_from_symbol(&symbol));
    }
}