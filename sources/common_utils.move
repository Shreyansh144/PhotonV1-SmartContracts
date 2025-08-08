module PhotonResourceAddress::common_utils {
    use std::vector;
    use std::signer;
    use std::option;

    /// Generic pair vector map: vector<(address, V)>
    public fun index_of_addr<V: copy + drop + store>(arr: &vector::Vector<(address, V)>, key: address): option::Option<u64> {
        let len = vector::length(arr);
        let mut i = 0u64;
        while (i < len) {
            let pair_ref = vector::borrow(arr, i);
            let (a, _) = *pair_ref;
            if (a == key) {
                return option::some(i);
            };
            i = i + 1;
        };
        option::none()
    }

    public fun borrow_by_index<V: copy + drop + store>(arr: &vector::Vector<(address, V)>, i: u64): & (address, V) {
        vector::borrow(arr, i)
    }

    public fun remove_by_index<V: copy + drop + store>(arr: &mut vector::Vector<(address, V)>, i: u64) {
        // swap_remove-like: move last to i, pop_back
        let last = vector::length(arr) - 1;
        if (i < last) {
            let last_pair = *vector::borrow(arr, last);
            vector::borrow_mut(arr, i).0 = last_pair.0;
            vector::borrow_mut(arr, i).1 = last_pair.1;
        };
        vector::pop_back(arr);
    }

    public fun assert_signer_is(s: &signer, expected: address) {
        let addr = signer::address_of(s);
        assert!(addr == expected, 1);
    }
}
