// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module axelar::channel {
    use std::ascii::String;
    use sui::table::{Self, Table};
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::event;

    friend axelar::validators;

    /// Generic target for the messaging system.
    ///
    /// This struct is required on the Sui side to be the destination for the
    /// messages sent from other chains. Even though it has a UID field, it does
    /// not have a `key` ability to force wrapping.
    ///
    /// Notes:
    ///
    /// - Does not have key to prevent 99% of the mistakes related to access management.
    /// Also prevents arbitrary Message destruction if the object is shared. Lastly,
    /// when shared, `Channel` cannot be destroyed, and its contents will remain locked
    /// forever.
    ///
    /// - Allows asset or capability-locking inside. Some applications might
    /// authorize admin actions through the bridge (eg by locking some `AdminCap`
    /// inside and getting a `&mut AdminCap` in the `consume_message`);
    ///
    /// - Can be destroyed freely as the `UID` is guaranteed to be unique across
    /// the system. Destroying a channel would mean the end of the Channel cycle
    /// and all further messages will have to target a new Channel if there is one.
    ///
    /// - Does not contain direct link to the state in Sui, as some functions
    /// might not take any specific data (eg allow users to create new objects).
    /// If specific object on Sui is targeted by this `Channel`, its reference
    /// should be implemented using the `data` field.
    ///
    /// - The funniest and extremely simple implementation would be a `Channel<ID>`
    /// since it actually contains the data required to point at the object in Sui.

    /// For when trying to consume the wrong object.
    const EWrongDestination: u64 = 0;
    /// For when message has already been processed and submitted twice.
    const EDuplicateMessage: u64 = 2;

    /// The Channel object. Acts as a destination for the messages sent through
    /// the bridge. The `target_id` is compared against the `id` of the `Channel`
    /// during the message consumption.
    ///
    /// The `T` parameter allows wrapping a Capability or a piece of data into
    /// the channel to be used when the message is consumed (eg authorize a
    /// `mint` call using a stored `AdminCap`).
    public struct Channel has key, store {
        /// Unique ID of the target object which allows message targeting
        /// by comparing against `id_bytes`.
        id: UID,
        /// Messages processed by this object for the current axelar epoch. To make system less
        /// centralized, and spread the storage + io costs across multiple
        /// destinations, we can track every `Channel`'s messages.
        processed_call_approvals: Table<address, bool>,
    }

    /// A HotPotato - call received from the Gateway. Must be delivered to the
    /// matching Channel, otherwise the TX fails.
    public struct ApprovedCall {
        /// ID of the call approval, guaranteed to be unique by Axelar.
        cmd_id: address,
        /// The target Channel's UID.
        target_id: address,
        /// Name of the chain where this approval came from.
        source_chain: String,
        /// Address of the source chain (vector used for compatibility).
        /// UTF8 / ASCII encoded string (for 0x0... eth address gonna be 42 bytes with 0x)
        source_address: String,
        /// Payload of the command.
        payload: vector<u8>,
    }

    // ====== Events ======

    public struct ChannelCreated has copy, drop {
        id: address,
    }

    public struct ChannelDestroyed has copy, drop {
        id: address,
    }

    /// Create new `Channel` object. Anyone can create their own `Channel` to target
    /// from the outside and there's no limitation to the data stored inside it.
    ///
    /// `copy` ability is required to disallow asset locking inside the `Channel`.
    public fun new(ctx: &mut TxContext): Channel {
        let id = object::new(ctx);
        event::emit(ChannelCreated { id: id.uid_to_address() });

        Channel {
            id,
            processed_call_approvals: table::new(ctx),
        }
    }

    /// Destroy a `Channen` releasing the T. Not constrained and can be performed
    /// by any party as long as they own a Channel.
    public fun destroy(self: Channel) {
        let Channel { id, processed_call_approvals } = self;

        processed_call_approvals.drop();
        event::emit(ChannelDestroyed { id: id.uid_to_address() });
        id.delete();
    }

    /// Create a new `ApprovedCall` object to be sent to another chain. Is called
    /// by the gateway when a message is "picked up" by the relayer.
    public(friend) fun create_approved_call(
        cmd_id: address,
        source_chain: String,
        source_address: String,
        target_id: address,
        payload: vector<u8>,
    ): ApprovedCall {
        ApprovedCall {
            cmd_id,
            source_chain,
            source_address,
            target_id,
            payload
        }
    }

    /// Consume a approved call hot potato object sent to this `Channel` from another chain.
    /// For Capability-locking, a mutable reference to the `Channel.data` field is returned.
    ///
    /// Returns a mutable reference to the locked T, the `source_chain`, the `source_address`
    /// and the `payload` to be used by the consuming application.
    public fun consume_approved_call(
        channel: &mut Channel,
        approved_call: ApprovedCall
    ): (String, String, vector<u8>) {
        let ApprovedCall {
            cmd_id,
            target_id,
            source_chain,
            source_address,
            payload,
        } = approved_call;

        // Check if the message has already been processed.
        assert!(!channel.processed_call_approvals.contains(cmd_id), EDuplicateMessage);
        // Check if the message is sent to the correct destination.
        assert!(target_id == object::id_address(channel), EWrongDestination);

        channel.processed_call_approvals.add(cmd_id, true);

        (
            source_chain,
            source_address,
            payload,
        )
    }

    // === Testing ===

    #[test_only]
    public fun burn_approved_call_for_testing(call: ApprovedCall) {
        let ApprovedCall {
            cmd_id: _,
            target_id: _,
            source_chain: _,
            source_address: _,
            payload: _,
        } = call;
    }
}
