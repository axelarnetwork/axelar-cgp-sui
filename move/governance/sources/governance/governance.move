module governance::governance {
    use sui::object::{Self, ID, UID};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::bcs;

    struct Governance has key {
        id: UID,
        caps: Table<ID, UpgradeCap>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(
            Governance{
                id: object::new(ctx),
                caps: table::new<ID, UpgradeCap>(ctx),
            }
        )
    }

    public fun register_package(self: &mut Governance, upgrade_cap: UpgradeCap) {
        let cap_id = object::id(&upgrade_cap);
        table::add(&mut self.caps, cap_id, upgrade_cap);
    }
    public fun issue_upgrate(self: &mut Governance, command: vector<u8>, signatures: vector<u8>): UpgradeTicket {
        let bcs = bcs::new(command);
        let cap_id = bcs::peel_address(&mut bcs);
        let policy = bcs::peel_u8(&mut bcs);
        let digest = bcs::peel_vec_u8(&mut bcs);
        let cap = table::borrow_mut(&mut self.caps, object::id_from_address(cap_id));
        package::authorize_upgrade(
            cap,
            policy,
            digest,
        )
    }

    public fun commit_upgrade(self: &mut Governance, receipt: UpgradeReceipt) {
        let cap_id = package::receipt_cap(&receipt);
        let cap = table::borrow_mut(&mut self.caps, cap_id);
        package::commit_upgrade(
            cap,
            receipt,
        );
    }
}