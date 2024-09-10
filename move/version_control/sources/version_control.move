/// This module implements a custom version control scheme to maximize versioning customizability.
module version_control::version_control;

use sui::vec_set::{Self, VecSet};

// ------
// Errors
// ------
/// This is thrown when the function is not supported in the version passed on `check`
const EFunctionNotSupported: u64 = 0;

// -----
// Types
// -----
public struct VersionControl has store, copy, drop {
    allowed_functions: vector<VecSet<vector<u8>>>,
}

// ----------------
// Public Functions
// ----------------

/// Create a new Version Controll object by passing raw allowed_functions data.
/// You are supposed to pass a vector of the bytes of the functions that are allowed per version. For example:
/// vector [
///     vector [ b"v0_function" ],
///     vector [ b"v0_function", b"v1_function"],
/// ]
/// Would allow only `v0_function` to be called on version == 0, and both `v0_function` and `v1_function` to be called on version == 1.
/// This is done to simplify the instantiation syntax of VersionControl.
public fun new(allowed_functions: vector<vector<vector<u8>>>): VersionControl {
    VersionControl {
        allowed_functions: allowed_functions.map!(
            |function_names| vec_set::from_keys(
                function_names
            )
        )
    }
}

/// This allowes for anyone to modify the raw data of allowed functions.
/// Do not pass a mutable reference of your VersionControl to anyone you do not trust because they can modify it.
public fun allowed_functions(self: &mut VersionControl): &mut vector<VecSet<vector<u8>>> {
    &mut self.allowed_functions
}

/// If a new version does not need to deprecate any old functions, you can use this to add the newly supported functions.
public fun push_back(self: &mut VersionControl, function_names: vector<vector<u8>>) {
    self.allowed_functions.push_back(
        vec_set::from_keys(
            function_names
        )
    );
}

/// Call this at the begining of each version controlled function. For example
/// public fun do_something(data: &mut DataType) {
///     data.version_control.check(VERSION, b"do_something");
///     // do the thing.
/// }
public fun check(self: &VersionControl, version: u64, function: vector<u8>) {
    assert!(self.allowed_functions[version].contains(&function), EFunctionNotSupported);
}
