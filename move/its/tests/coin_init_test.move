#[test_only]
module its::thecool1234coin___ {
    use sui::tx_context::{Self, TxContext};
    use sui::coin;
    use std::option;
    use sui::url::{Url};
    use sui::transfer;

    public struct THECOOL1234COIN___ has drop{

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
        // use sui::test_scenario::{Self as ts, ctx};
        use sui::tx_context::dummy;

        init(THECOOL1234COIN___{}, &mut dummy());
    }
}
