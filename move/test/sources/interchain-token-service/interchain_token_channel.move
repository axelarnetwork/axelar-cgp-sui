

/// Todo: consider nuking?
module its::interchain_token_channel {
    use sui::tx_context::{Self, TxContext};

    /// Identifies a token channel.
    struct TokenChannel has store, drop {
        id: address,
    }

    /// Creates a new token channel.
    public fun new(ctx: &mut TxContext): TokenChannel {
        TokenChannel { id: tx_context::fresh_object_address(ctx) }
    }

    /// Returns the address of the token channel.
    public fun to_address(self: &TokenChannel): address { self.id }
}
