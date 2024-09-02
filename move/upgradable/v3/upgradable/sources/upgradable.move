// Change the fields of singleton all together, beaking backwards compatibility.
module upgradable::upgradable {
    use std::ascii::{Self, String};

    use sui::dynamic_field;
    use sui::event;

    use version_control::version_control::{Self, VersionControl};

    const VERSION: u64 = 2;
    const FUNCTION_INDEX_SET: u8 = 0;
    const FUNCTION_INDEX_GET: u8 = 1;
    const FUNCTION_INDEX_SET_TAG: u8 = 2;
    const FUNCTION_INDEX_GET_TAG: u8 = 3;

    const EIncorrectVersion: u64 = 0;

    public struct Singleton has key {
        id: UID,
    }

    public struct DataV0 has store {
        value: u64,
        version: u64,
        version_control: VersionControl,
    }

    public struct DataV1 has store {
        value: u64,
        version: u64,
        version_control: VersionControl,
        // Add another field here
        tag: String,
    }

    public struct ValueSet has copy, drop {
        value: u64,
    }

    entry fun upgrade(self: &mut Singleton) {
        let DataV0 { value, version, version_control: _} = dynamic_field::remove(&mut self.id, 0);
        assert!(version < VERSION, EIncorrectVersion);

        let version_control = version_control::new(vector[
            vector[],
            vector[],
            vector[
                FUNCTION_INDEX_GET, FUNCTION_INDEX_SET, FUNCTION_INDEX_GET_TAG
            ],
        ]);

        let data = DataV1 {
            value,
            version: VERSION,
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

    public fun set_tag(self: &mut Singleton, tag: String) {
        let data = self.borrow_data_mut();
        data.version_control.check(FUNCTION_INDEX_SET_TAG, VERSION);
        data.tag = tag;
    }

    public fun get_tag(self: &Singleton): String {
        let data = self.borrow_data();
        data.version_control.check(FUNCTION_INDEX_GET_TAG, VERSION);
        data.tag
    }
}