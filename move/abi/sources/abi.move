/// This module implements ABI encoding/decoding methods for interoperability
/// with EVM message format.
///
/// ABI Specification: https://docs.soliditylang.org/en/v0.8.26/abi-spec.html
module abi::abi;

use sui::bcs;

// ---------
// Constants
// ---------
const U256_BYTES: u64 = 32;

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
/// Creates a new AbiReader from the bytes passed.
public fun new_reader(bytes: vector<u8>): AbiReader {
    AbiReader {
        bytes,
        head: 0,
        pos: 0,
    }
}

/// Creates a new `AbiWriter` that can fit up to length bytes before to
/// overflows.
public fun new_writer(length: u64): AbiWriter {
    AbiWriter {
        bytes: vector::tabulate!(U256_BYTES * length, |_| 0),
        pos: 0,
    }
}

/// Retrieve the bytes from an `AbiWriter`.
public fun into_bytes(self: AbiWriter): vector<u8> {
    let AbiWriter { bytes, pos: _ } = self;

    bytes
}

/// Retrieve the bytes from an `AbiWriter`.
// TODO: check that all bytes were decoded
public fun into_remaining_bytes(self: AbiReader): vector<u8> {
    let AbiReader { bytes, head: _, pos: _ } = self;

    bytes
}

/// Read a `u256` from the next slot of the `AbiReader`. Should be used to read
/// other fixed length types as well.
public fun read_u256(self: &mut AbiReader): u256 {
    let mut var = 0u256;
    let pos = self.pos;

    U256_BYTES.do!(|i| var = (var << 8) | (self.bytes[i + pos] as u256));

    self.pos = pos + U256_BYTES;

    var
}

/// Wrapper for `read_u256` that casts the result into a `u8`.
public fun read_u8(self: &mut AbiReader): u8 {
    self.read_u256() as u8
}

/// Used to ignore the next variable in an `AbiReader`.
public fun skip_slot(self: &mut AbiReader) {
    self.pos = self.pos + U256_BYTES;
}

/// Reads a variable length variable from an `AbiReader`, as bytes. Can be
/// converted to other variable length variables as well (such as `Strings`).
public fun read_bytes(self: &mut AbiReader): vector<u8> {
    let pos = self.pos;

    // Move position to the start of the bytes
    let offset = self.read_u256() as u64;
    self.pos = self.head + offset;

    let var = self.decode_bytes();

    // Move position to the next slot
    self.pos = pos + U256_BYTES;

    var
}

/// Reads a vector of fixed length variables from an `AbiReader` as a
/// `vector<u256>`. Can also be cast into vectors of other fixed length
/// variables.
public fun read_vector_u256(self: &mut AbiReader): vector<u256> {
    let mut var = vector[];
    let pos = self.pos;

    // Move position to the start of the dynamic data
    let offset = self.read_u256() as u64;
    self.pos = self.head + offset;

    let length = self.read_u256() as u64;

    length.do!(|_| var.push_back(self.read_u256()));

    self.pos = pos + U256_BYTES;

    var
}

/// Reads a vector of variable length variables from an `AbiReader` as a
/// `vector<vector<u8>>`. Can also be cast into vectors of other variable length
/// variables.
public fun read_vector_bytes(self: &mut AbiReader): vector<vector<u8>> {
    let mut var = vector[];

    let pos = self.pos;
    let head = self.head;

    // Move position to the start of the dynamic data
    let offset = self.read_u256() as u64;
    self.pos = head + offset;

    let length = self.read_u256() as u64;
    self.head = self.pos;

    length.do!(|_| var.push_back(self.read_bytes()));

    // Move position to the next slot
    self.pos = pos + U256_BYTES;
    self.head = head;

    var
}

/// Reads the raw bytes of a variable length variable. This will return
/// additional bytes at the end of the structure as there is no way to know how
/// to decode the bytes returned. This can be used to decode structs and complex
/// nested vectors that this library does not provide a method for. For example
/// if a user calls `read_bytes_raw` to decode encoded an encoded `bytes`
/// variable this will return 32 bytes that contain the length of the encoded
/// `bytes`, followed by all remaining bytes in the `AbiReader`. To decode
/// these, a user can first parse the length from the first 32 bytes and then
/// parse the subsection of the remaining bytes with that length into a
/// `vector<u8>` (which should yield the same result as calling `read_bytes` on
/// the original `AbiReader` instead of `read_bytes_raw`).
public fun read_bytes_raw(self: &mut AbiReader): vector<u8> {
    // Move position to the start of the bytes
    let offset = self.read_u256() as u64;
    let length = self.bytes.length() - offset;

    let mut var = vector[];
    length.do!(|i| var.push_back(self.bytes[offset + i]));

    var
}

/// Write a `u256` into the next slot of an `AbiWriter`. Can be used to write
/// other fixed lenght variables as well.
public fun write_u256(self: &mut AbiWriter, var: u256): &mut AbiWriter {
    let pos = self.pos;

    U256_BYTES.do!(|i| {
        let exp = ((31 - i) * 8 as u8);
        let byte = (var >> exp & 255 as u8);
        *&mut self.bytes[i + pos] = byte;
    });

    self.pos = pos + U256_BYTES;

    self
}

/// Write a `u8` into the next slot of an `AbiWriter`.
public fun write_u8(self: &mut AbiWriter, var: u8): &mut AbiWriter {
    self.write_u256(var as u256)
}

/// Write some bytes into the next slot of an `AbiWriter`. Can be used to write
/// another variable length variable, such as a `String`as well.
public fun write_bytes(self: &mut AbiWriter, var: vector<u8>): &mut AbiWriter {
    let offset = self.bytes.length() as u256;
    self.write_u256(offset);

    // Write dynamic data length and bytes at the tail
    self.append_u256(var.length() as u256);
    self.append_bytes(var);

    self
}

/// Write a `vector<u256>` into the next slot of an `AbiWriter`. Can be used to
/// encode other vectors of fixed length variables as well.
public fun write_vector_u256(
    self: &mut AbiWriter,
    var: vector<u256>,
): &mut AbiWriter {
    let offset = self.bytes.length() as u256;
    self.write_u256(offset);

    let length = var.length();
    self.append_u256(length as u256);

    var.do!(|val| {
        self.append_u256(val)
    });

    self
}

/// Write a vector of bytes into the next slot of an `AbiWriter`. Can be used to
/// encode vectors of other variable length variables as well.
public fun write_vector_bytes(
    self: &mut AbiWriter,
    var: vector<vector<u8>>,
): &mut AbiWriter {
    let offset = self.bytes.length() as u256;
    self.write_u256(offset);

    let length = var.length();
    self.append_u256(length as u256);

    let mut writer = new_writer(length);
    var.do!(|val| {
        writer.write_bytes(val);
    });

    self.append_bytes(writer.into_bytes());

    self
}

/// Write raw bytes to the next slot of an `AbiWriter`. This can be used to
/// write structs or more nested arrays that we support in this module.
public fun write_bytes_raw(
    self: &mut AbiWriter,
    var: vector<u8>,
): &mut AbiWriter {
    let offset = self.bytes.length() as u256;
    self.write_u256(offset);

    self.append_bytes(var);

    self
}

// ------------------
// Internal Functions
// ------------------
fun append_u256(self: &mut AbiWriter, var: u256) {
    let mut bytes = bcs::to_bytes(&var);
    bytes.reverse();
    self.bytes.append(bytes)
}

fun append_bytes(self: &mut AbiWriter, var: vector<u8>) {
    let length = var.length();
    if (length == 0) {
        return
    };

    self.bytes.append(var);

    (31 - (length - 1) % 32).do!(|_| self.bytes.push_back(0));
}

fun decode_bytes(self: &mut AbiReader): vector<u8> {
    let length = self.read_u256() as u64;
    let pos = self.pos;

    let mut bytes = vector[];

    length.do!(|i| bytes.push_back(self.bytes[i + pos]));

    bytes
}

// -----
// Tests
// -----
#[test]
fun test_u256() {
    let input = 56;
    let output =
        x"0000000000000000000000000000000000000000000000000000000000000038";

    let mut writer = new_writer(1);
    writer.write_u256(input);
    assert!(writer.into_bytes() == output);

    let mut reader = new_reader(output);
    assert!(reader.read_u256() == input);
}

#[test]
fun test_skip_slot() {
    let input = 56;
    let output =
        x"00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000038";

    let mut writer = new_writer(2);
    writer.write_u256(1).write_u256(input);
    assert!(writer.into_bytes() == output);

    let mut reader = new_reader(output);
    reader.skip_slot();
    assert!(reader.read_u256() == input);
}

#[test]
fun test_read_bytes() {
    let input = x"123456";
    let output =
        x"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000031234560000000000000000000000000000000000000000000000000000000000";

    let mut writer = new_writer(1);
    writer.write_bytes(input);
    assert!(writer.into_bytes() == output);

    let mut reader = new_reader(output);
    assert!(reader.read_bytes() == input);
}

#[test]
fun test_read_vector_u256() {
    let input = vector[1, 2, 3];
    let output =
        x"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003";

    let mut writer = new_writer(1);
    writer.write_vector_u256(input);
    assert!(writer.into_bytes() == output);

    let mut reader = new_reader(output);
    assert!(reader.read_vector_u256() == input);
}

#[test]
fun test_read_vector_bytes() {
    let input = vector[x"01", x"02", x"03", x"04"];
    let output =
        x"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000102000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010400000000000000000000000000000000000000000000000000000000000000";

    let mut writer = new_writer(1);
    writer.write_vector_bytes(input);
    assert!(writer.into_bytes() == output);

    let mut reader = new_reader(output);
    assert!(reader.read_vector_bytes() == input);
}

#[test]
fun test_multiple() {
    let (input1, input2, input3, input4) = (1, x"02", vector[3], vector[x"04"]);
    let output =
        x"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010400000000000000000000000000000000000000000000000000000000000000";

    let mut writer = new_writer(4);
    writer.write_u256(input1);
    writer.write_bytes(input2);
    writer.write_vector_u256(input3);
    writer.write_vector_bytes(input4);
    assert!(writer.into_bytes() == output);

    let mut reader = new_reader(output);
    assert!(reader.read_u256() == input1);
    assert!(reader.read_bytes() == input2);
    assert!(reader.read_vector_u256() == input3);
    assert!(reader.read_vector_bytes() == input4);
}

#[test]
fun test_raw_struct() {
    let number = 3;
    let data = b"data";

    let mut writer = new_writer(1);
    let mut struct_writer = new_writer(2);
    struct_writer.write_u256(number).write_bytes(data);
    writer.write_bytes_raw(struct_writer.into_bytes());

    let bytes = writer.into_bytes();

    let mut reader = new_reader(bytes);

    let struct_bytes = reader.read_bytes_raw();

    let mut struct_reader = new_reader(struct_bytes);

    assert!(struct_reader.read_u256() == number);
    assert!(struct_reader.read_bytes() == data);
}

#[test]
fun test_raw_table() {
    let table = vector[vector[1, 2, 3], vector[4, 5, 6]];

    let mut writer = new_writer(1);

    let length = table.length();

    let mut length_writer = new_writer(1);
    length_writer.write_u256(length as u256);
    let mut bytes = length_writer.into_bytes();

    let mut table_writer = new_writer(length);
    table.do!(|row| {
        table_writer.write_vector_u256(row);
    });
    bytes.append(table_writer.into_bytes());

    writer.write_bytes_raw(bytes);

    let bytes = writer.into_bytes();

    let mut reader = new_reader(bytes);

    let mut table_bytes = reader.read_bytes_raw();
    let mut length_bytes = vector[];

    // Split the data into the lenth and the actual table contents
    U256_BYTES.do!(|_| length_bytes.push_back(table_bytes.remove(0)));

    let mut length_reader = new_reader(length_bytes);
    let length = length_reader.read_u256();

    let mut table_read = vector[];
    let mut table_reader = new_reader(table_bytes);
    length.do!(|_| table_read.push_back(table_reader.read_vector_u256()));

    assert!(table_read == table);
}
