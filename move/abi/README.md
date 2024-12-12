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
More complex types are not supported yet.

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

#### Example
```rust
let mut reader = abi::new_reader(data);
let number = reader.read_u256();
let name = reader.read_bytes().to_string();
let addresses = reader.read_vector_u256().map!(|val| sui::address::from_u256(val));
let info = reader.read_vector_bytes();
```

#### More Complex Types

More complex types are not supported yet.
