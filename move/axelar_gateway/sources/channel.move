module axelar_gateway::channel {
    use std::ascii::String;
    use sui::table::{Self, Table};
    use sui::event;

    use axelar_gateway::bytes32::{Bytes32};
    use axelar_gateway::message::{Self};

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
    /// the bridge. The `destination_id` is compared against the `id` of the `Channel`
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
        message_approvals: Table<Bytes32, bool>,
    }

    /// A HotPotato - call received from the Gateway. Must be delivered to the
    /// matching Channel, otherwise the TX fails.
    public struct ApprovedMessage {
        /// Name of the chain where this approval came from.
        source_chain: String,
        /// Unique ID of the message.
        message_id: String,
        /// Address of the source chain.
        /// UTF8 / ASCII encoded string (for 0x0... eth address gonna be 42 bytes with 0x)
        source_address: String,
        /// The destination Channel's UID.
        destination_id: address,
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
            message_approvals: table::new(ctx),
        }
    }

    /// Destroy a `Channel` releasing the T. Not constrained and can be performed
    /// by any party as long as they own a Channel.
    public fun destroy(self: Channel) {
        let Channel { id, message_approvals } = self;

        message_approvals.drop();
        event::emit(ChannelDestroyed { id: id.uid_to_address() });
        id.delete();
    }

    public fun id(self: &Channel): ID {
        object::id(self)
    }

    public fun to_address(self: &Channel): address {
        object::id_address(self)
    }

    /// Create a new `ApprovedMessage` object to be sent to another chain. Is called
    /// by the gateway when a message is "picked up" by the relayer.
    public(package) fun create_approved_message(
        source_chain: String,
        message_id: String,
        source_address: String,
        destination_id: address,
        payload: vector<u8>,
    ): ApprovedMessage {
        ApprovedMessage {
            source_chain,
            message_id,
            source_address,
            destination_id,
            payload
        }
    }

    /// Consume an approved message hot potato object sent to this `Channel` from another chain.
    /// For Capability-locking, a mutable reference to the `Channel.data` field is returned.
    ///
    /// Returns a mutable reference to the locked T, the `source_chain`, the `source_address`
    /// and the `payload` to be used by the consuming application.
    public fun consume_approved_message(
        channel: &mut Channel,
        approved_message: ApprovedMessage
    ): (String, String, String, vector<u8>) {
        let ApprovedMessage {
            source_chain,
            message_id,
            source_address,
            destination_id,
            payload,
        } = approved_message;
        let command_id = message::message_to_command_id(source_chain, message_id);

        // Check if the message has already been processed.
        assert!(!channel.message_approvals.contains(command_id), EDuplicateMessage);

        // Check if the message is sent to the correct destination.
        assert!(destination_id == object::id_address(channel), EWrongDestination);

        channel.message_approvals.add(command_id, true);

        (
            source_chain,
            message_id,
            source_address,
            payload,
        )
    }

    #[test_only]
    public fun create_test_approved_message(
        source_chain: String,
        message_id: String,
        source_address: String,
        destination_id: address,
        payload: vector<u8>,
    ): ApprovedMessage {
        create_approved_message(
            source_chain,
            message_id,
            source_address,
            destination_id,
            payload,
        )
    }

    #[test]
    fun test_new_and_destroy() {
        let ctx = &mut sui::tx_context::dummy();
        let channel: Channel = new(ctx);
        channel.destroy()
    }

    #[test]
    fun test_id() {
        let ctx = &mut sui::tx_context::dummy();
        let channel: Channel = new(ctx);
        assert!(channel.id() == object::id(&channel), 0);
        channel.destroy()
    }


    #[test]
    fun test_to_address() {
        let ctx = &mut sui::tx_context::dummy();
        let channel: Channel = new(ctx);
        assert!(channel.to_address() == object::id_address(&channel), 0);
        channel.destroy()
    }

    #[test]
    fun test_create_approved_message() {
        let input_source_chain = std::ascii::string(b"Source Chain");
        let input_message_id = std::ascii::string(b"message id");
        let input_source_address = std::ascii::string(b"Source Address");
        let input_destination_id = @0x5678;
        let input_payload = b"payload";
        let approved_message: ApprovedMessage = create_approved_message(
            input_source_chain,
            input_message_id,
            input_source_address,
            input_destination_id,
            input_payload
        );

        let ApprovedMessage {
            source_chain,
            message_id,
            source_address,
            destination_id,
            payload
        } = approved_message;
        assert!(source_chain == input_source_chain, 0);
        assert!(message_id == input_message_id, 1);
        assert!(source_address == input_source_address, 2);
        assert!(destination_id == input_destination_id, 3);
        assert!(payload == input_payload, 4);
    }

    #[test]
    fun test_consume_approved_message() {
        let ctx = &mut sui::tx_context::dummy();
        let mut channel: Channel = new(ctx);

        let input_source_chain = std::ascii::string(b"Source Chain");
        let input_message_id = std::ascii::string(b"message id");
        let input_source_address = std::ascii::string(b"Source Address");
        let input_destination_id = channel.to_address();
        let input_payload = b"payload";
        let approved_message: ApprovedMessage = create_approved_message(
            input_source_chain,
            input_message_id,
            input_source_address,
            input_destination_id,
            input_payload,
        );

        let (source_chain, message_id, source_address, payload) = consume_approved_message(&mut channel, approved_message);

        assert!(source_chain == input_source_chain, 1);
        assert!(message_id == input_message_id, 3);
        assert!(source_address == input_source_address, 2);
        assert!(payload == input_payload, 4);

        channel.destroy();
    }

    #[test]
    #[expected_failure(abort_code = EDuplicateMessage)]
    fun test_consume_approved_message_duplicate_message() {
        let ctx = &mut sui::tx_context::dummy();
        let mut channel: Channel = new(ctx);

        let source_chain = std::ascii::string(b"Source Chain 1");
        let message_id = std::ascii::string(b"message id 1");

        let source_address1 = std::ascii::string(b"Source Address 1");
        let destination_id1 = channel.to_address();
        let payload1 = b"payload 1";
        let source_address2 = std::ascii::string(b"Source Address");
        let destination_id2 = channel.to_address();
        let payload2 = b"payload 2";

        consume_approved_message(&mut channel, create_approved_message(
            source_chain,
            message_id,
            source_address1,
            destination_id1,
            payload1,
        ));

        consume_approved_message(&mut channel, create_approved_message(
            source_chain,
            message_id,
            source_address2,
            destination_id2,
            payload2,
        ));

        channel.destroy();
    }

    #[test]
    #[expected_failure(abort_code = EWrongDestination)]
    fun test_consume_approved_message_wrong_destination() {
        let ctx = &mut sui::tx_context::dummy();
        let mut channel: Channel = new(ctx);

        let source_chain = std::ascii::string(b"Source Chain");
        let message_id = std::ascii::string(b"message id");
        let source_address = std::ascii::string(b"Source Address");
        let destination_id = @0x5678;
        let payload = b"payload";

        let approved_message = create_approved_message(
            source_chain,
            message_id,
            source_address,
            destination_id,
            payload,
        );

        consume_approved_message(&mut channel, approved_message);

        channel.destroy();
    }
}
