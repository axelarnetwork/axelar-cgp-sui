// Added an event when setting the value
module upgradable::upgradable {
    use sui::dynamic_field;
    use sui::event;

    use version_control::version_control::{Self, VersionControl};

    const VERSION: u64 = 1;
    const FUNCTION_INDEX_SET: u8 = 0;
    const FUNCTION_INDEX_GET: u8 = 1;

    const EIncorrectVersion: u64 = 0;

    public struct Singleton has key {
        id: UID,
    }

    public struct DataV0 has store {
        value: u64,
        version: u64,
        version_control: VersionControl,
    }

    public struct ValueSet has copy, drop {
        value: u64,
    }

    entry fun upgrade(self: &mut Singleton) {
        let data = self.borrow_data_mut();
        assert!(data.version < VERSION, EIncorrectVersion);
        data.version = VERSION;
        data.version_control = version_control::new(vector[
            vector[
                FUNCTION_INDEX_GET,
            ],
            vector[
                FUNCTION_INDEX_GET, FUNCTION_INDEX_SET,
            ],
        ]);
    }

    fun borrow_data(self: &Singleton): &DataV0 {
        dynamic_field::borrow(&self.id, 0)
    }

    fun borrow_data_mut(self: &mut Singleton): &mut DataV0 {
        dynamic_field::borrow_mut(&mut self.id, 0)
    }

    public fun set(self: &mut Singleton, value: u64) {
        let data = self.borrow_data_mut();
        data.version_control.check(FUNCTION_INDEX_SET, VERSION);
        data.value = value;
        event::emit({
            ValueSet{
                value,
            }
        });
    }

    public fun get(self: &Singleton): u64 {
        let data = self.borrow_data();
        data.version_control.check(FUNCTION_INDEX_GET, VERSION);
        data.value
    }
}