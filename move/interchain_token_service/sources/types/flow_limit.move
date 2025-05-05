module interchain_token_service::flow_limit {
    use sui::clock::Clock;

    const EPOCH_TIME: u64 = 6 * 60 * 60 * 1000;

    #[error]
    const EFlowLimitExceeded: vector<u8> = b"flow limit exceeded";

    public struct FlowLimit has copy, drop, store {
        flow_limit: Option<u64>,
        flow_in: u128,
        flow_out: u128,
        current_epoch: u64,
    }

    public(package) fun new(): FlowLimit {
        FlowLimit {
            flow_limit: option::none(),
            flow_in: 0,
            flow_out: 0,
            current_epoch: 0,
        }
    }

    fun update_epoch(self: &mut FlowLimit, clock: &Clock) {
        let epoch = clock.timestamp_ms() / EPOCH_TIME;
        if (epoch > self.current_epoch) {
            self.current_epoch = epoch;
            self.flow_in = 0;
            self.flow_out = 0;
        }
    }

    public(package) fun add_flow_in(self: &mut FlowLimit, amount: u64, clock: &Clock) {
        if (self.flow_limit.is_none()) {
            return
        };
        let flow_limit = *self.flow_limit.borrow() as u128;

        update_epoch(self, clock);
        assert!(self.flow_in + (amount as u128) < flow_limit + self.flow_out, EFlowLimitExceeded);
        self.flow_in = self.flow_in + (amount as u128);
    }

    public(package) fun add_flow_out(self: &mut FlowLimit, amount: u64, clock: &Clock) {
        if (self.flow_limit.is_none()) {
            return
        };
        let flow_limit = *self.flow_limit.borrow() as u128;

        update_epoch(self, clock);
        assert!(self.flow_out + (amount as u128) < flow_limit + self.flow_in, EFlowLimitExceeded);
        self.flow_out = self.flow_out + (amount as u128);
    }

    public(package) fun set_flow_limit(self: &mut FlowLimit, flow_limit: Option<u64>) {
        self.flow_limit = flow_limit;
    }

    // -----
    // Tests
    // -----
    #[test]
    fun test_update_epoch() {
        let ctx = &mut tx_context::dummy();
        let mut flow_limit = new();
        let mut clock = sui::clock::create_for_testing(ctx);
        flow_limit.update_epoch(&clock);
        clock.increment_for_testing(EPOCH_TIME);
        flow_limit.update_epoch(&clock);
        clock.destroy_for_testing();
    }

    #[test]
    fun test_add_flow_in() {
        let ctx = &mut tx_context::dummy();
        let mut flow_limit = new();
        let clock = sui::clock::create_for_testing(ctx);
        flow_limit.set_flow_limit(option::some(2));
        flow_limit.add_flow_in(1, &clock);
        clock.destroy_for_testing();
    }

    #[test]
    fun test_add_flow_out() {
        let ctx = &mut tx_context::dummy();
        let mut flow_limit = new();
        let clock = sui::clock::create_for_testing(ctx);
        flow_limit.set_flow_limit(option::some(2));
        flow_limit.add_flow_out(1, &clock);
        clock.destroy_for_testing();
    }

    #[test]
    fun test_add_flow_in_zero_flow_limit() {
        let ctx = &mut tx_context::dummy();
        let mut flow_limit = new();
        let clock = sui::clock::create_for_testing(ctx);
        flow_limit.add_flow_in(1, &clock);
        clock.destroy_for_testing();
    }

    #[test]
    fun test_add_flow_out_zero_flow_limit() {
        let ctx = &mut tx_context::dummy();
        let mut flow_limit = new();
        let clock = sui::clock::create_for_testing(ctx);
        flow_limit.add_flow_out(1, &clock);
        clock.destroy_for_testing();
    }

    #[test]
    #[expected_failure(abort_code = EFlowLimitExceeded)]
    fun test_add_flow_in_limit_exceeded() {
        let ctx = &mut tx_context::dummy();
        let mut flow_limit = new();
        let clock = sui::clock::create_for_testing(ctx);
        flow_limit.set_flow_limit(option::some(1));
        flow_limit.add_flow_in(1, &clock);
        clock.destroy_for_testing();
    }

    #[test]
    #[expected_failure(abort_code = EFlowLimitExceeded)]
    fun test_add_flow_out_limit_exceeded() {
        let ctx = &mut tx_context::dummy();
        let mut flow_limit = new();
        let clock = sui::clock::create_for_testing(ctx);
        flow_limit.set_flow_limit(option::some(1));
        flow_limit.add_flow_out(1, &clock);
        clock.destroy_for_testing();
    }
}
