// The base module that has no events.
module upgradable::upgradable {
    use sui::dynamic_field;

    use version_control::version_control::{Self, VersionControl};

    const VERSION: u64 = 0;

    public struct Singleton has key {
        id: UID,
    }

    public struct DataV0 has store {
        value: u64,
        version_control: VersionControl,
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
}