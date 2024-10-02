module its::interchain_transfer_ticket;

use its::token_id::TokenId;
use std::ascii::String;
use sui::balance::Balance;

/// -----
/// Types
/// -----
#[allow(lint(coin_field))]
public struct InterchainTransferTicket<phantom T> {
    token_id: TokenId,
    balance: Balance<T>,
    source_address: address,
    destination_chain: String,
    destination_address: vector<u8>,
    metadata: vector<u8>,
    version: u64,
}

// -----------------
// Package Functions
// -----------------
public(package) fun new<T>(
    token_id: TokenId,
    balance: Balance<T>,
    source_address: address,
    destination_chain: String,
    destination_address: vector<u8>,
    metadata: vector<u8>,
    version: u64,
): InterchainTransferTicket<T> {
    InterchainTransferTicket<T> {
        token_id,
        balance,
        source_address,
        destination_chain,
        destination_address,
        metadata,
        version,
    }
}

public(package) fun destroy<T>(
    self: InterchainTransferTicket<T>,
): (TokenId, Balance<T>, address, String, vector<u8>, vector<u8>, u64) {
    let InterchainTransferTicket<T> {
        token_id,
        balance,
        source_address,
        destination_chain,
        destination_address,
        metadata,
        version,
    } = self;
    (
        token_id,
        balance,
        source_address,
        destination_chain,
        destination_address,
        metadata,
        version,
    )
}
