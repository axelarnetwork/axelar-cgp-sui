module governance::governance {
    use std::ascii::String;
    use std::type_name;
    use std::ascii;

    use sui::object::{Self, ID, UID};
    use sui::tx_context::TxContext;
    use sui::table::{Self, Table};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::address;
    use sui::transfer;
    use sui::hex;

    use axelar::utils::{abi_decode_fixed, abi_decode_variable};
    use axelar::channel::{Self, Channel, ApprovedCall};

    const EUntrustedAddress: u64 = 0;
    const EInvalidMessageType: u64 = 1;
    const ENotSelfUpgradeCap: u64 = 2;
    const ENotNewPackage: u64 = 3;

    struct Governance has key, store {
        id: UID,
        trusted_source_chain: String,
        trusted_source_address: String,
        message_type: u256,
        channel: Channel,
        caps: Table<ID, UpgradeCap>,
    }

    // This can only be called once since it needs its own upgrade cap which it deletes.
    public fun new(
        trusted_source_chain: String,
        trusted_source_address: String,
        message_type: u256,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext,
    ) {
        let package_id = object::id_from_bytes(
            hex::decode(
                ascii::into_bytes(
                    type_name::get_address(
                        &type_name::get<Governance>()
                    )
                )
            )
        );
        assert!(package::upgrade_package(&upgrade_cap) == package_id, ENotSelfUpgradeCap);
        is_cap_new(&upgrade_cap);
        package::make_immutable(upgrade_cap);

        transfer::share_object(Governance{
            id: object::new(ctx),
            trusted_source_chain,
            trusted_source_address,
            message_type,
            channel: channel::new(ctx),
            caps: table::new<ID, UpgradeCap>(ctx),
        })
    }
    

    public fun is_governance(
        self: &Governance, 
        chain_name: String, 
        addr: String
    ): bool{
        &chain_name == &self.trusted_source_chain && &addr == &self.trusted_source_address
    }

    // TODO maybe check that the polcy for the upgrade cap has not been tampered with.
    public fun take_upgrade_cap(self: &mut Governance, upgrade_cap: UpgradeCap) {
        is_cap_new(&upgrade_cap);

        table::add(
            &mut self.caps,
            object::id(&upgrade_cap),
            upgrade_cap,
        )
    }

    public fun authorize_upgrade(self: &mut Governance, approved_call: ApprovedCall): UpgradeTicket {
        let (source_chain, source_address, payload) = channel::consume_approved_call(
            &mut self.channel, 
            approved_call,
        );

        assert!(is_governance(self, source_chain, source_address), EUntrustedAddress);

        let message_type = abi_decode_fixed(&payload, 0);
        assert!(message_type == self.message_type, EInvalidMessageType);

        let cap_id = object::id_from_address(address::from_u256(abi_decode_fixed(&payload, 1)));
        let policy = (abi_decode_fixed(&payload, 2) as u8);
        let digest = abi_decode_variable(&payload, 3);

        package::authorize_upgrade(
            table::borrow_mut(&mut self.caps, cap_id), 
            policy, 
            digest,
        )
    }

    public fun commit_upgrade(
        self: &mut Governance,
        receipt: UpgradeReceipt,
    ) {
        package::commit_upgrade(
            table::borrow_mut(
                &mut self.caps, 
                package::receipt_cap(&receipt),
            ), 
            receipt
        )
    }

    
    fun is_cap_new(cap: &UpgradeCap) {
        assert!(package::version(cap) == 0, ENotNewPackage);
    }
}