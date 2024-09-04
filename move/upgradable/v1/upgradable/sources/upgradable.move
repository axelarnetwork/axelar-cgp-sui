// The base module that has no events.
module upgradable::upgradable {
    use sui::dynamic_field;
    use sui::bcs;

    use version_control::version_control::{Self, VersionControl};

    const VERSION: u64 = 0;
    
    const ENoFutureTickets: u64 = 0;
    const ERemainingData: u64 = 1;

    // This singleton can have dynamic fields enabling it to bu mutable.
    public struct Singleton has key {
        id: UID,
    }

    // This is the first version of the data, which will exist as a dynamic field for as long as this structure is supported.
    public struct DataV0 has store {
        value: u64,
        version_control: VersionControl,
    }
    
    // This will be prepeared by a function that should never be depreceted and will be proccesed by another function that might.
    public struct Ticket {
        data: vector<u8>,
        version: u64,
    }

    fun init(ctx: &mut TxContext) {
        let mut id = object::new(ctx);
        let version_control = version_control::new(vector[
            vector[b"get", b"set"],
        ]);

        dynamic_field::add(&mut id, 0, DataV0 {
            value: 0,
            version_control,
        });

        transfer::share_object(Singleton {
            id,
        });
    }

    fun borrow_data(self: &Singleton): &DataV0 {
        dynamic_field::borrow<u64, DataV0>(&self.id, 0)
    }

    fun borrow_data_mut(self: &mut Singleton): &mut DataV0 {
        dynamic_field::borrow_mut<u64, DataV0>(&mut self.id, 0)
    }

    public fun set(self: &mut Singleton, value: u64) {
        let data = self.borrow_data_mut();
        data.version_control.check(b"set", VERSION);
        data.value = value;
    }

    public fun get(self: &Singleton): u64 {
        let data = self.borrow_data();
        data.version_control.check(b"get", VERSION);
        data.value
    }

    // This function should never be deprecated so no version checking is done.
    // We can forbid 
    public fun prepeare_ticket(data: vector<u8>): Ticket {
        Ticket {
            data,
            version: VERSION,
        }
    }

    public fun commit(self: &mut Singleton, ticket: Ticket) {
        let data = self.borrow_data_mut();
        data.version_control.check(b"commit", VERSION);

        let Ticket { data: ticket_data, version } = ticket;
        assert!(VERSION >= version, ENoFutureTickets );
        let mut bcs = bcs::new(ticket_data);
        data.value = bcs.peel_u64();
        assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);
    }
}