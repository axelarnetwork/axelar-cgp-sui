module abi::abi {

    public struct AbiReader has copy, drop {
        bytes: vector<u8>,
    }

    public struct AbiWriter has copy, drop {
        bytes: vector<u8>,
        pos: u64,
    }

    public fun new_reader(bytes: vector<u8>): AbiReader {
        AbiReader {
            bytes,
        }
    }

    public fun new_writer(length: u64): AbiWriter {
        let mut bytes = vector::empty<u8>();
        let mut i = 0;
        while (i < 32 * length) {
            vector::push_back<u8>(&mut bytes, 0);
            i = i + 1;
        };
        AbiWriter {
            bytes,
            pos: 0,
        }
    }

    public fun into_bytes(self: AbiWriter): vector<u8> {
        let AbiWriter {bytes, pos: _} = self;
        bytes
    }

    public fun read_u256(self: &AbiReader, pos: u64): u256 {
        let mut var = 0u256;
        let mut i = 0;
        while (i < 32) {
            var = var << 8;
            var = var | (*vector::borrow(&self.bytes, i + 32 * pos) as u256);
            i = i + 1;
        };
        var
    }

    public fun read_bytes(self: &AbiReader, pos: u64): vector<u8> {
        let start_pos = (self.read_u256(pos) as u64) / 32;
        let var = self.decode_variable(start_pos);
        var
    }

    public fun read_vector_u256(self: &AbiReader, pos: u64): vector<u256> {
        let start_pos = (self.read_u256(pos) as u64) / 32;
        let length = (self.read_u256(start_pos) as u64);
        let mut var = vector::empty<u256>();
        let mut i = 0;
        while (i < length) {
            vector::push_back(&mut var, self.read_u256(start_pos + i + 1));
            i = i + 1;
        };
        var
    }

    public fun read_vector_bytes(self: &AbiReader, pos: u64): vector<vector<u8>> {
        let start_pos = (self.read_u256(pos) as u64) / 32;
        let length = (self.read_u256(start_pos) as u64);
        let mut var = vector::empty<vector<u8>>();
        let mut i = 0;
        while (i < length) {
            let start_pos_nested = (self.read_u256(start_pos + i + 1) as u64) / 32;
            vector::push_back(&mut var, self.decode_variable(start_pos + start_pos_nested + 1));
            i = i + 1;
        };
        var
    }

    public fun write_u256(self: &mut AbiWriter, var: u256): &mut AbiWriter {
        let pos = self.pos;
        self.encode_u256(pos, var);
        self.pos = self.pos + 1;
        self
    }

    public fun write_bytes(self: &mut AbiWriter, var: vector<u8>): &mut AbiWriter {
        let pos = self.pos;
        let mut length = vector::length(&self.bytes);
        self.encode_u256(pos, (length as u256));

        length = vector::length(&var);
        self.append_u256((length as u256));

        self.append_bytes(var);
        self.pos = self.pos + 1;
        self
    }

    public fun write_vector_u256(self: &mut AbiWriter, var: vector<u256>): &mut AbiWriter {
        let pos = self.pos;
        let mut length = vector::length(&self.bytes);
        self.encode_u256(pos, (length as u256));
        
        length = vector::length(&var);

        self.append_u256((length as u256));

        let mut i = 0;
        while (i < length) {
            self.append_u256(*vector::borrow(&var, i));
            i = i + 1;
        };

        self.pos = self.pos + 1;
        self
    }

    public fun write_vector_bytes(self: &mut AbiWriter, var: vector<vector<u8>>): &mut AbiWriter {
        let pos = self.pos;
        let mut length = vector::length(&self.bytes);
        self.encode_u256(pos, (length as u256));
        
        length = vector::length(&var);

        self.append_u256((length as u256));

        let mut i = 0;
        let mut writer = new_writer(length);
        while (i < length) {
            writer.write_bytes(*vector::borrow(&var, i));
            i = i + 1;
        };

        self.append_bytes(writer.into_bytes());

        self.pos = self.pos + 1;
        self
    }

    fun encode_u256(self: &mut AbiWriter, pos: u64, var: u256) {
        let v = &mut self.bytes;
        let mut i = 0;
        while (i < 32) {
            let val = vector::borrow_mut<u8>(v, i + 32 * pos);
            let exp = ((31 - i) * 8 as u8);
            *val = (var >> exp & 255 as u8);
            i = i + 1;
        };
    }

    fun append_u256(self: &mut AbiWriter, var: u256) {
        let v = &mut self.bytes;
        let mut i = 0;
        while (i < 32) {
            vector::push_back(v, ((var >> ((31 - i) * 8 as u8)) & 255 as u8));
            i = i + 1;
        };
    }

    fun append_bytes(self: &mut AbiWriter, var: vector<u8>) {
        let length = vector::length(&var);

        let v = &mut self.bytes;
        vector::append(v, var);
        if (length == 0) {
            return
        };

        let mut i: u64 = 0;
        while (i < 31 - (length - 1) % 32) {
            vector::push_back(v, 0);
            i = i + 1;
        };
    }

    fun decode_variable(self: &AbiReader, start_pos: u64): vector<u8> {
        let v = &self.bytes;
        let len = (self.read_u256(start_pos) as u64);
        let mut var = vector::empty();
        let mut i = 0;
        while (i < len) {
            vector::push_back(&mut var, *vector::borrow(v, i + (start_pos + 1) * 32));
            i = i + 1;
        };
        var
    }

    #[test]
    fun test_u256() {
        let input = 56;
        let output = x"0000000000000000000000000000000000000000000000000000000000000038";

        let mut writer = new_writer(1);
        writer.write_u256(input);
        assert!(writer.into_bytes() == output, 0);

        let reader = new_reader(output);
        assert!(reader.read_u256(0) == input, 1);
    }

    #[test]
    fun test_read_bytes() {
        let input = x"123456";
        let output = x"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000031234560000000000000000000000000000000000000000000000000000000000";

        let mut writer = new_writer(1);
        writer.write_bytes(input);
        assert!(writer.into_bytes() == output, 0);

        let reader = new_reader(output);
        assert!(reader.read_bytes(0) == input, 1);
    }

    #[test]
    fun test_read_vector_u256() {
        let input = vector[1, 2, 3];
        let output = x"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003";

        let mut writer = new_writer(1);
        writer.write_vector_u256(input);
        assert!(writer.into_bytes() == output, 0);

        let reader = new_reader(output);
        assert!(reader.read_vector_u256(0) == input, 1);
    }

    #[test]
    fun test_read_vector_bytes() {
        let input = vector[x"01", x"02", x"03"];
        let output = x"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010300000000000000000000000000000000000000000000000000000000000000";

        let mut writer = new_writer(1);
        writer.write_vector_bytes(input);
        assert!(writer.into_bytes() == output, 0);

        let reader = new_reader(output);
        assert!(reader.read_vector_bytes(0) == input, 1);
    }

    #[test]
    fun test_multiple() {
        let (input1, input2, input3, input4) = (1, x"02", vector[3], vector[x"04"]);
        let output = x"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010400000000000000000000000000000000000000000000000000000000000000";

        let mut writer = new_writer(4);
        writer.write_u256(input1);
        writer.write_bytes(input2);
        writer.write_vector_u256(input3);
        writer.write_vector_bytes(input4);
        assert!(writer.into_bytes() == output, 0);

        let reader = new_reader(output);
        assert!(reader.read_u256(0) == input1, 1);
        assert!(reader.read_bytes(1) == input2, 2);
        assert!(reader.read_vector_u256(2) == input3, 3);
        assert!(reader.read_vector_bytes(3) == input4, 4);
    }
}