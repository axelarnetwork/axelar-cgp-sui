# Abi

This package aims to port abi encoding and decoding capabilities to Sui. Read more about the specification of abi encoding [here](https://docs.soliditylang.org/en/develop/abi-spec.html#formal-specification-of-the-encoding)

## Singletons

There are no singletons in this package.

## Types

There are two types exported by this package: `AbiWriter` and `AbiReader`.

### `AbiWriter`

This type can be used to encode abi data. It has the following relevant functions:
- `abi::new_writer(length: u64): AbiWriter`: Creates a new `AbiWriter` with the specified length (number of encoded arguments)
- `abi::into_bytes(self: AbiWriter): vector<u8>`: Destroys an `AbiWriter` and returns the encoded bytes for it.
- `abi::write_u256(self: &mut AbiWriter, var: u256): &mut AbiWriter`: Writes the provided `u256` into the next slot in the `AbiWriter`. This should be used to write all fixed length variables (`u8`, `u16`, `u32`, `u64`, `u128`, `address` for example) by converting them to `u256`.
- `abi::write_u8(self: &mut AbiWriter, var: u8): &mut AbiWriter`: Wrapper for the above for `u8` specifically.
- `abi::write_bytes(self: &mut AbiWriter, var: vector<u8>): &mut AbiWriter`: Writes the provided bytes into the next slot in the `AbiWriter`. This should be used to write all types that are equivelant to `vector<u8>` (`ascii::String` and `string::String` for example) by converting them to `vector<u8>`.
- `abi::write_vector_u256(self: &mut AbiWriter, var: vector<u256>,): &mut AbiWriter`: Writes the provided `vector<u256>` into the next slot in the  `AbiWriter`. This should be used for vectors of other fixed length variables as well.
- `abi::write_vector_bytes(self: &mut AbiWriter, var: vector<vector<u8>>,): &mut AbiWriter`: Writes the provided `vector<vector<u8>>` into the nexts slot in the `AbiWriter`. This should be used for vectors of other variable length variables as well.
- `abi::write_bytes_raw(self: &mut AbiWriter, var: vector<u8>,): &mut AbiWriter`: Writes the raw bytes provided to the next slot of the `AbiWriter`. These bytes are not length prefixed, and can therefore not be decoded as bytes. The purpose of this function is to allow for encoding of more complex, unavailable structs.

#### Example
```rust
let mut writer = abi::new_writer(4);
writer
    .write_u256(1234)
    .write_bytes(b"some_bytes")
    .write_vector_u256(vector[12, 34, 56])
    .write_vector_bytes(vector[b"some", b"more", b"bytes"]);
let encoded_data = writer.into_bytes();
```

#### More complex types
More complex types are curently not supported. This is because Sui Move does not support any sort of type inspection (like `is_vector<T>`) to recursively encode vectors. However with `abi::write_bytes_raw` these types can be encoded with some extra work from the user.
For example to encode a struct consisting of  `u256` called `number` and a `vector<u8>` called `data` into an `AbiWriter` named `writer` a user could do
```rust
let mut struct_writer = new_writer(2);
struct_writer
    .write_u256(number)
    .write_bytes(data);
writer
    .write_bytes_raw(struct_writer.into_bytes());
```
As another example, to abi encode a `vector<vector<u256>>` named `table` into an `AbiWriter` named `writer` a user could do
```rust
let length = table.length();

let mut length_writer = new_writer(1);
length_writer.write_u256(length as u256);
let mut bytes = length_writer.into_bytes();

let mut table_writer = new_writer(length);
table.do!(|row| {
    table_writer.write_vector_u256(row);
});
bytes.append(table_writer.into_bytes());

writer
    .write_bytes_raw(bytes);
```

### `AbiReader`

This type can be used to decode abi enocded data. The relevant functions are as follows:
- `abi::new_reader(bytes: vector<u8>): AbiReader`: Creates a new `AbiReader` to decode the bytes provided.
- `abi::into_remaining_bytes(self: AbiReader): vector<u8>`: Get all the bytes stored in the `AbiReader` (name is misleading).
- `abi::read_u256(self: &mut AbiReader): u256`: Read a `u256` from the next slot of the `AbiReader`. Should be used to read other fixed length types as well. 
- `abi::read_u8(self: &mut AbiReader): u8`: Wrapper for the above function for `u8`.
- `abi::skip_slot(self: &mut AbiReader)`: Used to ingore a slot on the `AbiReader`, used if it has data encoded there that should be ignored.
- `abi::read_bytes(self: &mut AbiReader): vector<8>`: Read a `vector<u8>` from the next slot of the `AbiReader`. Should be used to read other variable length types as well.
- `abi::read_vector_u256(self: &mut AbiReader): vector<u256>`: Read a `vector<u256>` from the next slot of the `AbiReader`. Should be used to read other fixed length types as well.
- `abi::read_vector_bytes(self: &mut AbiReader): vector<vector<u8>>`: Read a `vector<vector<u8>>` from the next slot of the `AbiReader`. Should be used to read other vectors of variable length types as well (such as `vector<ascii::String>`).
- `abi::read_bytes_raw(self: &mut AbiReader): vector<u8>`: Read the raw bytes encoded in the next slot of the `AbiReader`. This will include any bytes encoded after the raw bytes desired which should be ignored.

#### Example
```rust
let mut reader = abi::new_reader(data);
let number = reader.read_u256();
let name = reader.read_bytes().to_string();
let addresses = reader.read_vector_u256().map!(|val| sui::address::from_u256(val));
let info = reader.read_vector_bytes();
```

#### More Complex Types

For more complex types like structs or nested vectors `read_bytes_raw` can be used and decoded. For to read a struct that contains a `u256` and a `vector<u8>` from an `AbiReader` called `reader` a user may:
```rust
    let struct_bytes = reader.read_bytes_raw();

    let mut struct_reader = new_reader(struct_bytes);
    let number = struct_reader.read_u256();
    let data = struct_reader.read_bytes();
```
As another example, to decode a `vector<vector<u256>>` into a variable called table from an `AbiReader` called `reader` a user can:
```rust
let mut table_bytes = reader.read_bytes_raw();
let mut length_bytes = vector[];

// Split the data into the lenth and the actual table contents.
32u64.do!(|_| length_bytes.push_back(table_bytes.remove(0)));

let mut length_reader = new_reader(length_bytes);
let length = length_reader.read_u256();

let mut table = vector[];
let mut table_reader = new_reader(table_bytes);
length.do!(|_| table.push_back(table_reader.read_vector_u256()));
```

