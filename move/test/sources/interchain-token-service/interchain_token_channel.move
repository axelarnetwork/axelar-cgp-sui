


module interchain_token_service::interchain_token_channel {
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    
    struct TokenChannel has store {
        id: UID,
    }

    public fun new(ctx: &mut TxContext): TokenChannel {
        TokenChannel {
            id: object::new(ctx),
        }
    }

    public fun to_address(token_channel: &TokenChannel): address {
        object::uid_to_address(&token_channel.id)
    }
}