module example::utils;


public fun concat<T: copy>(v1: vector<T>, v2: vector<T>): vector<T> {
    let mut result = v1;
    vector::append(&mut result, v2);
    result
}
