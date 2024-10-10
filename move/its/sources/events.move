module its::events;

use its::token_id::TokenId;
use sui::event;

// -----
// Types
// -----
public struct CoinRegistered<phantom T> has copy, drop {
    token_id: TokenId,
}

// -----------------
// Package Functions
// -----------------
public(package) fun coin_registered<T>(token_id: TokenId) {
    event::emit(CoinRegistered<T> {
        token_id,
    });
}
