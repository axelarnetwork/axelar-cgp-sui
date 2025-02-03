module version_control::test {
    public struct Test {
        val: u256,
    }

    public fun new(val: u256): Test {
        Test {
            val,
        }
    }
}
