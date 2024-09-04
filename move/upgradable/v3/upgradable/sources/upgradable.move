// Change the fields of singleton all together, beaking backwards compatibility.
module upgradable::upgradable {
    use std::ascii::{Self, String};

    use sui::dynamic_field;
    use sui::event;

    use version_control::version_control::{Self, VersionControl};

    const VERSION: u64 = 2;

    const EIncorrectVersion: u64 = 0;

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
}