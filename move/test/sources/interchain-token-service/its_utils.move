

module interchain_token_service::its_utils {
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
        while(isNumber(*vector::borrow(symbolBytes, i))) {
            i = i + 1;
        };
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

    public fun decode_metadata(metadata: vector<u8>): (u32, vector<u8>) {
        if(vector::length(&metadata) < 4) {
            (0, vector::empty<u8>())
        } else {
            let i = 0;
            let version: u32 = 0;
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

module interchain_token_service::thecool1234coin___ {
    use sui::tx_context::{Self, TxContext};
    use sui::coin;
    use std::option;
    use sui::url::{Url};
    use sui::transfer;

    struct THECOOL1234COIN___ has drop{

    }

    fun init(witness: THECOOL1234COIN___, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<THECOOL1234COIN___>(
            witness,
            6,
            b"THECOOL1234COIN___",
            b"",
            b"",
            option::none<Url>(),
            ctx
        );
        transfer::public_transfer(treasury, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
    }

    #[test]
    fun test_init() {
        use sui::test_scenario::{Self as ts, ctx};
        let test = ts::begin(@0x0);

        init(THECOOL1234COIN___{}, ctx(&mut test));



        ts::end(test);
    }
}