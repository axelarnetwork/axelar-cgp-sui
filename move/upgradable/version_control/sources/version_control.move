module version_control::version_control {
    const EVersionNotSupported: u64 = 0;

    public struct VersionControl has copy, store, drop {
        data: vector<u64>,
    }
    
    public fun new(versions: vector<vector<u8>>): VersionControl {
        let mut data = vector::empty<u64>();
        let length = versions.length();
        let mut i = 0;
        while (i < length) {
            data.push_back(collapse_function_indexes(versions[i]));
            i = i + 1;
        };
        VersionControl {
            data
        }
    }
    
    fun collapse_function_indexes(indexes: vector<u8>): u64 {
        let length = indexes.length();
        let mut i = 0;
        let mut val = 0;
        while(i < length) {
            val = val | ( 1 << indexes[i] );
            i = i + 1;
        };
        val
    }

    public fun check(self: &VersionControl, function: u8, version: u64) {
        assert!( (self.data[version] >> function) & 1 == 1, EVersionNotSupported);
    }
}
