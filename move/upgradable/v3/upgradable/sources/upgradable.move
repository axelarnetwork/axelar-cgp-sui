// Change the fields of singleton all together, beaking backwards compatibility.
module upgradable::upgradable {
    use std::ascii::{Self, String};

    use sui::dynamic_field;
    use sui::event;
    use sui::bcs;

    use version_control::version_control::{Self, VersionControl};

    const VERSION: u64 = 2;

    const ENoFutureTickets: u64 = 0;
    const ERemainingData: u64 = 1;
    const EIncorrectVersion: u64 = 2;

    public struct Singleton has key {
        id: UID,
    }

    public struct DataV0 has store {
        value: u64,
        version_control: VersionControl,
    }

    public struct DataV1 has store {
        value: u64,
        version_control: VersionControl,
        // Add another field here
        tag: String,
    }

    public struct ValueSet has copy, drop {
        value: u64,
    }

    // This will be prepeared by a function that should never be depreceted and will be proccesed by another function that might.
    public struct Ticket {
        data: vector<u8>,
        version: u64,
    }
    

    entry fun upgrade(self: &mut Singleton) {
        let DataV0 { value, mut version_control} = dynamic_field::remove(&mut self.id, 0);
        assert!(version_control.version() < VERSION, EIncorrectVersion);

        version_control = version_control::new(vector[
            vector[],
            vector[],
            vector[
                b"get", b"set", b"get_tag", b"set_tag",
            ],
        ]);

        let data = DataV1 {
            value,
            version_control,
            tag: ascii::string(b""),
        };
        dynamic_field::add(&mut self.id, 0, data);
    }

    fun borrow_data(self: &Singleton): &DataV1 {
        dynamic_field::borrow(&self.id, 0)
    }

    fun borrow_data_mut(self: &mut Singleton): &mut DataV1 {
        dynamic_field::borrow_mut(&mut self.id, 0)
    }

    public fun set(self: &mut Singleton, value: u64) {
        let data = self.borrow_data_mut();
        data.version_control.check(b"set", VERSION);
        data.value = value;
        event::emit({
            ValueSet{
                value,
            }
        });
    }

    public fun get(self: &Singleton): u64 {
        let data = self.borrow_data();
        data.version_control.check(b"get", VERSION);
        data.value
    }

    public fun set_tag(self: &mut Singleton, tag: String) {
        let data = self.borrow_data_mut();
        data.version_control.check(b"set_tag", VERSION);
        data.tag = tag;
    }

    public fun get_tag(self: &Singleton): String {
        let data = self.borrow_data();
        data.version_control.check(b"get_tag", VERSION);
        data.tag
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
        let value = bcs.peel_u64();
        data.value = value;
        data.tag = ascii::string(bcs.peel_vec_u8());
        assert!(bcs.into_remainder_bytes().length() == 0, ERemainingData);

        event::emit({
            ValueSet{
                value,
            }
        });
    }
    
}