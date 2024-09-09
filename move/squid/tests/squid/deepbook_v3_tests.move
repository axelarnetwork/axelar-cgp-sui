#[test_only]
module squid::deepbook_v3_tests {
use std::type_name::{Self, TypeName};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::object::id_to_address;
    use token::deep::DEEP;
    use deepbook::pool::Pool;
    use squid::deepbook_v3::{Self, DeepbookV3SwapData};
    use squid::swap_info;
    use sui::test_scenario::{Scenario, begin, end, return_shared};
    use sui::test_utils::{destroy, assert_eq};

    use deepbook::pool_tests;

    public struct USDC has store {}

    const OWNER: address = @0x1;

    #[test]
    fun test_serialize() {
        let mut test = begin(OWNER);
        let pool_id = pool_tests::setup_everything<
            SUI,
            USDC,
            SUI,
            DEEP,
        >(&mut test);

        test.next_tx(OWNER);
        let swap_data = deepbook_v3::new_swap_data(
            1,
            id_to_address(&pool_id),
            true,
            100,
            type_name::get<SUI>().into_string(),
            type_name::get<USDC>().into_string(),
            1,
            true,
        );
        let data = std::bcs::to_bytes(&swap_data);
        let mut swap_info = swap_info::new(data, test.ctx());
        let data2 = swap_info.get_data_estimating();
        let swap_data2 = deepbook_v3::peel_swap_data(data2);
        assert_eq(swap_data, swap_data2);

        let clock = test.take_shared<Clock>();
        let mut pool = test.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        destroy(pool);
        destroy(clock);
        destroy(swap_info);

        end(test);
    }
}