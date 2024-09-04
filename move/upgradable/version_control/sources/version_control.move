module version_control::version_control {
    use sui::vec_set::{Self, VecSet};
    const EVersionNotSupported: u64 = 0;

    public struct VersionControl has copy, store, drop {
        allowed_functions: vector<VecSet<vector<u8>>>,
    }
    
    public fun new(mut input: vector<vector<vector<u8>>>): VersionControl {
        let mut allowed_functions = vector::empty<VecSet<vector<u8>>>();
        let length = input.length();
        let mut i = 0;
        while (i < length) {
            let mut vec_set = vec_set::empty<vector<u8>>();
            let functions = &mut input[i];
            while (!functions.is_empty()) vec_set.insert(functions.pop_back());
            allowed_functions.push_back(vec_set);
            i = i + 1;
        };
        VersionControl {
            allowed_functions
        }
    }

    public fun version(self: &VersionControl): u64 {
        self.allowed_functions.length() - 1
    }

    public fun check(self: &VersionControl, function: vector<u8>, version: u64) {
        assert!( (self.allowed_functions[version].contains(&function)), EVersionNotSupported);
    }
}
