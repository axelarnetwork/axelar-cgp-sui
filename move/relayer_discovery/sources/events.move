module relayer_discovery::events {
    use relayer_discovery::transaction::Transaction;
    use sui::event;

    // ------
    // Events
    // ------
    /// Emitted when a transaction is registered
    public struct TransactionRegistered has copy, drop {
        channel_id: ID,
        transaction: Transaction,
    }

    /// Emitted when a transaction is removed
    public struct TransactionRemoved has copy, drop {
        channel_id: ID,
    }

    // -----------------
    // Package Functions
    // -----------------
    public(package) fun transaction_registered(channel_id: ID, transaction: Transaction) {
        event::emit(TransactionRegistered {
            channel_id,
            transaction,
        })
    }

    public(package) fun transaction_removed(channel_id: ID) {
        event::emit(TransactionRemoved {
            channel_id,
        })
    }
}
