module its::flow_limit;

use sui::clock::Clock;

const EPOCH_TIME: u64 = 6 * 60 * 60 * 1000;

const EFlowLimitExceeded: u64 = 0;

public struct FlowLimit has store, copy, drop {
    flow_limit: u64,
    flow_in: u64,
    flow_out: u64,
    current_epoch: u64,
}

public(package) fun new(): FlowLimit {
    FlowLimit {
        flow_limit: 0,
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

public(package) fun add_flow_in(
    self: &mut FlowLimit,
    amount: u64,
    clock: &Clock,
) {
    if (self.flow_limit == 0) return;

    update_epoch(self, clock);
    assert!(
        self.flow_in + amount < self.flow_limit + self.flow_out,
        EFlowLimitExceeded,
    );
    self.flow_in = self.flow_in + amount;
}

public(package) fun add_flow_out(
    self: &mut FlowLimit,
    amount: u64,
    clock: &Clock,
) {
    if (self.flow_limit == 0) return;

    update_epoch(self, clock);
    assert!(
        self.flow_out + amount < self.flow_limit + self.flow_in,
        EFlowLimitExceeded,
    );
    self.flow_out = self.flow_out + amount;
}

public(package) fun set_flow_limit(self: &mut FlowLimit, flow_limit: u64) {
    self.flow_limit = flow_limit;
}
