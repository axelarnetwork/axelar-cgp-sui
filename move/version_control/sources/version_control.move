/// This module implements a custom version control scheme to maximize
/// versioning customizability.
module version_control::version_control {
    use std::ascii::String;
    use sui::vec_set::{Self, VecSet};

    // ------
    // Errors
    // ------
    #[error]
    const EFunctionNotSupported: vector<u8> = b"function is not supported in this version";

    #[error]
    const EFunctionAlreadyAllowed: vector<u8> = b"trying to allow a function already allowed on the specified version";

    #[error]
    const EFunctionAlreadyDisallowed: vector<u8> = b"trying to disallow a function already disallowed on the specified version";

    // -----
    // Types
    // -----
    /// The function names are stored as Strings. They are however input as
    /// vector<u8> for ease of instantiation.
    public struct VersionControl has copy, drop, store {
        allowed_functions: vector<VecSet<String>>,
    }

    // ----------------
    // Public Functions
    // ----------------

    /// Create a new Version Control object by passing in the allowed_functions
    /// data.
    /// You are supposed to pass a vector of the bytes of the functions that are
    /// allowed per version. For example:
    /// ```
    /// vector [
    ///     vector [ b"v0_function" ],
    ///     vector [ b"v0_function", b"v1_function"],
    /// ]
    /// ```
    /// Would allow only `v0_function` to be called on version == 0, and both
    /// `v0_function` and `v1_function` to be called on version == 1.
    /// This is done to simplify the instantiation syntax of VersionControl.
    public fun new(allowed_functions: vector<vector<String>>): VersionControl {
        VersionControl {
            allowed_functions: allowed_functions.map!(
                |function_names| vec_set::from_keys(
                    function_names,
                ),
            ),
        }
    }

    /// This allowes for anyone to modify the raw data of allowed functions.
    /// Do not pass a mutable reference of your VersionControl to anyone you do not
    /// trust because they can modify it.
    public fun allowed_functions(self: &mut VersionControl): &mut vector<VecSet<String>> {
        &mut self.allowed_functions
    }

    /// If a new version does not need to deprecate any old functions, you can use
    /// this to add the newly supported functions.
    public fun push_back(self: &mut VersionControl, function_names: vector<String>) {
        self
            .allowed_functions
            .push_back(
                vec_set::from_keys(
                    function_names,
                ),
            );
    }

    public fun allow_function(self: &mut VersionControl, version: u64, function_name: String) {
        assert!(!self.allowed_functions[version].contains(&function_name), EFunctionAlreadyAllowed);
        self.allowed_functions[version].insert(function_name);
    }

    public fun disallow_function(self: &mut VersionControl, version: u64, function_name: String) {
        assert!(self.allowed_functions[version].contains(&function_name), EFunctionAlreadyDisallowed);
        self.allowed_functions[version].remove(&function_name);
    }

    /// Call this at the begining of each version controlled function. For example
    /// ```
    /// public fun do_something(data: &mut DataType) {
    ///     data.version_control.check(VERSION, b"do_something");
    ///     // do the thing.
    /// }
    /// ```
    public fun check(self: &VersionControl, version: u64, function: String) {
        assert!(self.allowed_functions[version].contains(&function), EFunctionNotSupported);
    }

    /// Returns the latest valid index in allowed functions.
    public fun latest_version(self: &VersionControl): u64 {
        self.allowed_functions.length() - 1
    }

    #[test]
    fun test_new() {
        let version_control = new(vector[vector[b"function_name_1"].map!(|function_name| function_name.to_ascii_string())]);
        assert!(version_control.allowed_functions.length() == 1);
        assert!(version_control.allowed_functions[0].contains(&b"function_name_1".to_ascii_string()));
        assert!(!version_control.allowed_functions[0].contains(&b"function_name_2".to_ascii_string()));
    }

    #[test]
    fun test_allowed_functions() {
        let mut version_control = new(vector[vector[b"function_name_1"].map!(|function_name| function_name.to_ascii_string())]);
        assert!(version_control.allowed_functions == version_control.allowed_functions());
    }

    #[test]
    fun test_push_back() {
        let mut version_control = new(vector[vector[b"function_name_1"].map!(|function_name| function_name.to_ascii_string())]);
        version_control.push_back(vector[b"function_name_1", b"function_name_2"].map!(|function_name| function_name.to_ascii_string()));
        assert!(version_control.allowed_functions.length() == 2);
        assert!(version_control.allowed_functions[0].contains(&b"function_name_1".to_ascii_string()));
        assert!(!version_control.allowed_functions[0].contains(&b"function_name_2".to_ascii_string()));
        assert!(version_control.allowed_functions[1].contains(&b"function_name_1".to_ascii_string()));
        assert!(version_control.allowed_functions[1].contains(&b"function_name_2".to_ascii_string()));
    }

    #[test]
    fun test_check() {
        let version_control = new(vector[vector[b"function_name_1"].map!(|function_name| function_name.to_ascii_string())]);
        version_control.check(0, b"function_name_1".to_ascii_string());
    }

    #[test]
    #[expected_failure(abort_code = EFunctionNotSupported)]
    fun test_check_function_not_supported() {
        let version_control = new(vector[vector[b"function_name_1"].map!(|function_name| function_name.to_ascii_string())]);
        version_control.check(0, b"function_name_2".to_ascii_string());
    }

    #[test]
    fun test_allow_function() {
        let version = 0;
        let function_name = b"function_name".to_ascii_string();
        let mut self = new(vector[vector[]]);

        self.allow_function(version, function_name);

        sui::test_utils::destroy(self);
    }

    #[test]
    fun test_disallow_function() {
        let version = 0;
        let function_name = b"function_name".to_ascii_string();
        let mut self = new(vector[vector[function_name]]);

        self.disallow_function(version, function_name);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EFunctionAlreadyAllowed)]
    fun test_allow_function_already_allowed() {
        let version = 0;
        let function_name = b"function_name".to_ascii_string();
        let mut self = new(vector[vector[function_name]]);

        self.allow_function(version, function_name);

        sui::test_utils::destroy(self);
    }

    #[test]
    #[expected_failure(abort_code = EFunctionAlreadyDisallowed)]
    fun test_disallow_function_already_disallowed() {
        let version = 0;
        let function_name = b"function_name".to_ascii_string();
        let mut self = new(vector[vector[]]);

        self.disallow_function(version, function_name);

        sui::test_utils::destroy(self);
    }

    #[test]
    fun test_latest_function() {
        let self = new(vector[vector[]]);

        assert!(self.latest_version() == 0);

        sui::test_utils::destroy(self);
    }
}
