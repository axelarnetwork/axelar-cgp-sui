

/// Todo: consider nuking?
module its::interchain_token_channel {
    use sui::tx_context::TxContext;

    /// Identifies a token channel.
    public struct TokenChannel has store, drop {
        id: address,
    }

    /// Creates a new token channel.
    public fun new(ctx: &mut TxContext): TokenChannel {
        TokenChannel { id: ctx.fresh_object_address() }
    }

    /// Returns the address of the token channel.
    public fun to_address(self: &TokenChannel): address { self.id }
}
