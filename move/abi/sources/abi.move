module abi::abi {
    // -----
    // Types
    // -----

    public struct AbiReader has copy, drop {
        bytes: vector<u8>,
        head: u64,
        pos: u64,
    }

    public struct AbiWriter has copy, drop {
        bytes: vector<u8>,
        pos: u64,
    }

    // ----------------
    // Public Functions
    // ----------------

    public fun new_reader(bytes: vector<u8>): AbiReader {
        AbiReader {
            bytes,
            head: 0,
            pos: 0,
        }
    }

    public fun new_writer(length: u64): AbiWriter {
        let mut bytes = vector[];
        let mut i = 0;

        while (i < 32 * length) {
            bytes.push_back(0);
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

    // TODO: check that all bytes were decoded
    public fun into_remaining_bytes(self: AbiReader): vector<u8> {
        let AbiReader {bytes, head: _, pos: _} = self;

        bytes
    }

    public fun read_u256_from_slot(self: &AbiReader, pos: u64): u256 {
        let mut var = 0u256;
        let mut i = 0;

        while (i < 32) {
            var = var << 8;
            var = var | (self.bytes[i + pos] as u256);
            i = i + 1;
        };

        var
    }

    public fun read_u256(self: &mut AbiReader): u256 {
        let mut var = 0u256;
        let mut i = 0;
        let pos = self.pos;

        while (i < 32) {
            var = (var << 8) | (self.bytes[i + pos] as u256);
            i = i + 1;
        };

        self.pos = pos + 32;

        var
    }

    public fun read_u8(self: &mut AbiReader): u8 {
        self.read_u256() as u8
    }

    public fun read_bytes(self: &mut AbiReader): vector<u8> {
        let pos = self.pos;

        // Move position to the start of the bytes
        let offset = self.read_u256() as u64;
        self.pos = self.head + offset;

        let bytes = self.decode_bytes();

        // Move position to the next slot
        self.pos = pos + 32;

        bytes
    }

    public fun read_vector_u256(self: &mut AbiReader): vector<u256> {
        let mut bytes = vector[];
        let pos = self.pos;

        // Move position to the start of the dynamic data
        let offset = self.read_u256() as u64;
        self.pos = self.head + offset;

        let length = self.read_u256() as u64;

        let mut i = 0;

        while (i < length) {
            bytes.push_back(self.read_u256());
            i = i + 1;
        };

        self.pos = pos + 32;

        bytes
    }

    /// Decode ABI-encoded 'bytes[]'
    public fun read_vector_bytes(self: &mut AbiReader): vector<vector<u8>> {
        let mut bytes = vector[];

        let pos = self.pos;
        let head = self.head;

        // Move position to the start of the dynamic data
        let offset = self.read_u256() as u64;
        self.pos = head + offset;

        let length = self.read_u256() as u64;
        self.head = self.pos;

        let mut i = 0;

        while (i < length) {
            bytes.push_back(self.read_bytes());

            i = i + 1;
        };

        // Move position to the next slot
        self.pos = pos + 32;
        self.head = head;

        bytes
    }

    public fun write_u256(self: &mut AbiWriter, var: u256): &mut AbiWriter {
        let pos = self.pos;
        self.encode_u256(pos, var);
        self.pos = self.pos + 1;
        self
    }

    public fun write_u8(self: &mut AbiWriter, var: u8): &mut AbiWriter {
        self.write_u256(var as u256)
    }

    public fun write_bytes(self: &mut AbiWriter, var: vector<u8>): &mut AbiWriter {
        let pos = self.pos;
        let length = self.bytes.length() as u256;
        self.encode_u256(pos, length);

        self.append_u256(var.length() as u256);

        self.append_bytes(var);
        self.pos = self.pos + 1;
        self
    }

    public fun write_vector_u256(self: &mut AbiWriter, var: vector<u256>): &mut AbiWriter {
        let pos = self.pos;
        let length = self.bytes.length();
        self.encode_u256(pos, length as u256);

        let length = var.length();
        self.append_u256(length as u256);

        let mut i = 0u64;
        while (i < length) {
            self.append_u256(var[i]);
            i = i + 1;
        };

        self.pos = self.pos + 1;
        self
    }

    public fun write_vector_bytes(self: &mut AbiWriter, var: vector<vector<u8>>): &mut AbiWriter {
        let pos = self.pos;
        let length = self.bytes.length();
        self.encode_u256(pos, length as u256);

        let length = var.length();
        self.append_u256(length as u256);

        let mut i = 0;
        let mut writer = new_writer(length);

        while (i < length) {
            writer.write_bytes(var[i]);
            i = i + 1;
        };

        self.append_bytes(writer.into_bytes());

        self.pos = self.pos + 1;
        self
    }

    // ------------------
    // Internal Functions
    // ------------------

    fun encode_u256(self: &mut AbiWriter, pos: u64, var: u256) {
        let mut i = 0;

        while (i < 32) {
            let exp = ((31 - i) * 8 as u8);
            *self.bytes.borrow_mut(i + 32 * pos) = (var >> exp & 255 as u8);
            i = i + 1;
        };
    }

    fun append_u256(self: &mut AbiWriter, var: u256) {
        let mut i = 0;
        while (i < 32) {
            self.bytes.push_back(((var >> ((31 - i) * 8 as u8)) & 255 as u8));
            i = i + 1;
        };
    }

    fun append_bytes(self: &mut AbiWriter, var: vector<u8>) {
        let length = var.length();
        if (length == 0) {
            return
        };

        self.bytes.append(var);

        let mut i = 0u64;

        while (i < 31 - (length - 1) % 32) {
            self.bytes.push_back(0);
            i = i + 1;
        };
    }

    fun decode_bytes(self: &mut AbiReader): vector<u8> {
        let length = self.read_u256() as u64;
        let pos = self.pos;

        let mut bytes = vector[];
        let mut i = 0;

        while (i < length) {
            bytes.push_back(self.bytes[i + pos]);
            i = i + 1;
        };

        bytes
    }

    // -----
    // Tests
    // -----

    #[test]
    fun test_u256() {
        let input = 56;
        let output = x"0000000000000000000000000000000000000000000000000000000000000038";

        let mut writer = new_writer(1);
        writer.write_u256(input);
        assert!(writer.into_bytes() == output, 0);

        let mut reader = new_reader(output);
        assert!(reader.read_u256() == input, 1);
    }

    #[test]
    fun test_read_bytes() {
        let input = x"123456";
        let output = x"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000031234560000000000000000000000000000000000000000000000000000000000";

        let mut writer = new_writer(1);
        writer.write_bytes(input);
        assert!(writer.into_bytes() == output, 0);

        let mut reader = new_reader(output);
        assert!(reader.read_bytes() == input, 1);
    }

    #[test]
    fun test_read_vector_u256() {
        let input = vector[1, 2, 3];
        let output = x"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003";

        let mut writer = new_writer(1);
        writer.write_vector_u256(input);
        assert!(writer.into_bytes() == output, 0);

        let mut reader = new_reader(output);
        assert!(reader.read_vector_u256() == input, 1);
    }

    #[test]
    fun test_read_vector_bytes() {
        let input = vector[x"01", x"02", x"03", x"04"];
        let output = x"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000102000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010400000000000000000000000000000000000000000000000000000000000000";

        let mut writer = new_writer(1);
        writer.write_vector_bytes(input);
        assert!(writer.into_bytes() == output, 0);

        let mut reader = new_reader(output);
        assert!(reader.read_vector_bytes() == input, 1);
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

        let mut reader = new_reader(output);
        assert!(reader.read_u256() == input1, 1);
        assert!(reader.read_bytes() == input2, 2);
        assert!(reader.read_vector_u256() == input3, 3);
        assert!(reader.read_vector_bytes() == input4, 4);
    }
}
