module its::events;

use axelar_gateway::bytes32::{Self, Bytes32};
use its::token_id::{TokenId, UnregisteredTokenId};
use std::ascii::String;
use std::string;
use sui::address;
use sui::event;
use sui::hash::keccak256;

// -----
// Types
// -----
public struct CoinRegistered<phantom T> has copy, drop {
    token_id: TokenId,
}

public struct InterchainTransfer<phantom T> has copy, drop {
    token_id: TokenId,
    source_address: address,
    destination_chain: String,
    destination_address: vector<u8>,
    amount: u256,
    data_hash: Bytes32,
}

public struct InterchainTokenDeploymentStarted<phantom T> has copy, drop {
    token_id: TokenId,
    name: string::String,
    symbol: String,
    decimals: u8,
    destination_chain: String,
}

public struct InterchainTransferReceived<phantom T> has copy, drop {
    message_id: String,
    token_id: TokenId,
    source_chain: String,
    source_address: vector<u8>,
    destination_address: address,
    amount: u256,
    data_hash: Bytes32,
}

public struct UnregisteredCoinReceived<phantom T> has copy, drop {
    token_id: UnregisteredTokenId,
    symbol: String,
    decimals: u8,
}

// -----------------
// Package Functions
// -----------------
public(package) fun coin_registered<T>(token_id: TokenId) {
    event::emit(CoinRegistered<T> {
        token_id,
    });
}

public(package) fun interchain_transfer<T>(
    token_id: TokenId,
    source_address: address,
    destination_chain: String,
    destination_address: vector<u8>,
    amount: u256,
    data: &vector<u8>,
) {
    let data_hash = bytes32::new(address::from_bytes(keccak256(data)));
    event::emit(InterchainTransfer<T> {
        token_id,
        source_address,
        destination_chain,
        destination_address,
        amount,
        data_hash,
    });
}

public(package) fun interchain_token_deployment_started<T>(
    token_id: TokenId,
    name: string::String,
    symbol: String,
    decimals: u8,
    destination_chain: String,
) {
    event::emit(InterchainTokenDeploymentStarted<T> {
        token_id,
        name,
        symbol,
        decimals,
        destination_chain,
    });
}

public(package) fun interchain_transfer_received<T>(
    message_id: String,
    token_id: TokenId,
    source_chain: String,
    source_address: vector<u8>,
    destination_address: address,
    amount: u256,
    data: &vector<u8>,
) {
    let data_hash = bytes32::new(address::from_bytes(keccak256(data)));
    event::emit(InterchainTransferReceived<T> {
        message_id,
        token_id,
        source_chain,
        source_address,
        destination_address,
        amount,
        data_hash,
    });
}

public(package) fun unregistered_coin_received<T>(
    token_id: UnregisteredTokenId,
    symbol: String,
    decimals: u8,
) {
    event::emit(UnregisteredCoinReceived<T> {
        token_id,
        symbol,
        decimals,
    });
}
