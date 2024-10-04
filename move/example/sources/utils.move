module example::utils;

/// ------
/// Public Functions
/// ------
public(package) fun concat<T: copy>(v1: vector<T>, v2: vector<T>): vector<T> {
    let mut result = v1;
    result.append(v2);
    result
}
