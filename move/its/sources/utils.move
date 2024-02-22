
module its::utils {
    use std::ascii;
    use std::vector;

    use sui::hash::keccak256;
    use sui::address;

    const LOWERCASE_START: u8 = 97;
    const UPPERCASE_START: u8 = 65;
    const NUMBERS_START: u8 = 48;
    const SPACE: u8 = 32;
    const UNDERSCORE: u8 = 95;

    public fun convert_value(val: u256): u64 {
        (val as u64)
    }

    public fun is_lowercase(c: u8): bool {
        c >= LOWERCASE_START && c <= LOWERCASE_START + 25
    }

    public fun is_uppercase(c: u8): bool {
        c >= UPPERCASE_START && c <= UPPERCASE_START + 25
    }

    public fun is_number(c: u8): bool {
        c >= NUMBERS_START && c <= NUMBERS_START + 9
    }

    public fun get_module_from_symbol(symbol: &ascii::String): ascii::String {
        let symbolBytes = ascii::as_bytes(symbol);
        let mut moduleName = vector[];

        let (mut i, length) = (0, vector::length(symbolBytes));
        while (is_number(*vector::borrow(symbolBytes, i))) {
            i = i + 1;
        };
        while (i < length) {
            let b = *vector::borrow(symbolBytes, i);
            if (is_lowercase(b) || is_number(b) ) {
                vector::push_back(&mut moduleName, b);
            } else if (is_uppercase(b) ) {
                vector::push_back(&mut moduleName, b - UPPERCASE_START + LOWERCASE_START);
            } else if (b == UNDERSCORE || b == SPACE) {
                vector::push_back(&mut moduleName, UNDERSCORE);
            };

            i = i + 1;
        };
        ascii::string(moduleName)
    }

    public fun hash_coin_info(symbol: &ascii::String, decimals: &u8): address {
        let mut v = vector[*decimals];
        vector::append(&mut v, *symbol.as_bytes());
        address::from_bytes(keccak256(&v))
    }

    public fun decode_metadata(mut metadata: vector<u8>): (u32, vector<u8>) {
        if (vector::length(&metadata) < 4) {
            (0, vector[])
        } else {
            let mut i = 0;
            let mut version: u32 = 0;
            while (i < 4) {
                version = (version << (8 as u8) as u32) + (vector::remove<u8>(&mut metadata, 0) as u32);
                i = i + 1;
            };

            (version, metadata)
        }
    }

    #[test]
    fun test_get_module_from_symbol() {
        let symbol = ascii::string(b"1(TheCool1234Coin) _ []!rdt");
        std::debug::print(&get_module_from_symbol(&symbol));
    }
}
