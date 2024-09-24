module axelar_gateway::events;

use std::ascii::String;

use sui::event;

use axelar_gateway::bytes32::Bytes32;
use axelar_gateway::weighted_signers::WeightedSigners;
use axelar_gateway::message::Message;


/// Emitted when signers are rotated.
public struct SignersRotated has copy, drop {
    epoch: u64,
    signers_hash: Bytes32,
    signers: WeightedSigners,
}

public(package) fun emit_signers_rotated(
    epoch: u64,
    signers_hash: Bytes32,
    signers: WeightedSigners,
) {
    event::emit(
        SignersRotated {
            epoch,
            signers_hash,
            signers,
        }
    );
}

/// Emitted when a new channel is created.
public struct ChannelCreated has copy, drop {
    id: address,
}

public(package) fun emit_channel_created(
    id: address,
) {
    event::emit(
        ChannelCreated {
            id
        }
    );
}

/// Emitted when a channel is destroyed.
public struct ChannelDestroyed has copy, drop {
    id: address,
}

public(package) fun emit_channel_destroyed(
    id: address,
) {
    event::emit(
        ChannelDestroyed {
            id
        }
    );
}

/// Emitted when a new message is sent from the SUI network.
public struct ContractCall has copy, drop {
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    payload_hash: address,
}

public(package) fun emit_contract_call(
    source_id: address,
    destination_chain: String,
    destination_address: String,
    payload: vector<u8>,
    payload_hash: address,
) {
    event::emit(
        ContractCall {    
            source_id,
            destination_chain,
            destination_address,
            payload,
            payload_hash,
        }
    );
}



/// Emitted when a new message is approved by the gateway.
public struct MessageApproved has copy, drop {
    message: Message,
}

public(package) fun emit_message_approved(
    message: Message,
) {
    event::emit(
        MessageApproved {
            message
        }
    );
}

/// Emitted when a message is taken to be executed by a channel.
public struct MessageExecuted has copy, drop {
    message: Message,
}

public(package) fun emit_message_executed(
    message: Message,
) {
    event::emit(
        MessageExecuted {
            message
        }
    );
}