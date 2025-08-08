module PhotonResourceAddress::user_registry {
    use std::vector;
    use std::signer;
    use std::timestamp;
    use PhotonResourceAddress::common_utils;

    struct UserData has copy, drop, store {
        identity_hash: vector<u8>, // SHA256 hash of email (as bytes)
        registered_at: u64,
        active: bool,
        wallet_balance: u128,
    }

    resource struct UserRegistry {
        owner: address, // admin address (resource stored at admin)
        users: vector::Vector<(address, UserData)>,
        created_at: u64,
    }

    public entry fun initialize(admin: &signer) {
        let addr = signer::address_of(admin);
        assert!(!exists<UserRegistry>(addr), 0);
        move_to(admin, UserRegistry {
            owner: addr,
            users: vector::empty(),
            created_at: timestamp::now_seconds(),
        });
    }

    /// Self-registration by user
    public entry fun create_new_user(user: &signer, identity_hash: vector<u8>) acquires UserRegistry {
        let addr = signer::address_of(user);
        assert!(exists<UserRegistry>(addr) || exists<UserRegistry>(borrow_global_address_of_resource()? ), 100);
        // Note: We store user registry at admin address, but we allow self-register if not already registered.
        // We will find the registry by scanning all accounts (simple approach): assume registry is deployed at admin signer address.
        // In practice, callers should call with admin signer to provide ownership; here we assume single admin account holds registry.
        // To keep simple: require that registry exists at the same address as deployer (we'll require admin to call initialize and then callers can call with user signers but we need owner address).
        let owner_addr = find_registry_owner();
        assert!(exists<UserRegistry>(owner_addr), 1);
        let reg = borrow_global_mut<UserRegistry>(owner_addr);
        let idx_opt = common_utils::index_of_addr(&reg.users, addr);
        assert!(option::is_none(&idx_opt), 2);

        let data = UserData {
            identity_hash,
            registered_at: timestamp::now_seconds(),
            active: true,
            wallet_balance: 0u128,
        };
        vector::push_back(&mut reg.users, (addr, data));
    }

    // Because we can't discover the owner in a simple prototype, provide helper where admin passes registry owner:
    public entry fun create_new_user_v2(reg_owner: &signer, user_addr: address, identity_hash: vector<u8>) acquires UserRegistry {
        let owner_addr = signer::address_of(reg_owner);
        assert!(exists<UserRegistry>(owner_addr), 3);
        let reg = borrow_global_mut<UserRegistry>(owner_addr);
        let idx_opt = common_utils::index_of_addr(&reg.users, user_addr);
        assert!(option::is_none(&idx_opt), 4);
        let data = UserData {
            identity_hash,
            registered_at: timestamp::now_seconds(),
            active: true,
            wallet_balance: 0u128,
        };
        vector::push_back(&mut reg.users, (user_addr, data));
    }

    public entry fun update_user_status(reg_owner: &signer, user_addr: address, active: bool) acquires UserRegistry {
        let owner_addr = signer::address_of(reg_owner);
        assert!(exists<UserRegistry>(owner_addr), 5);
        let reg = borrow_global_mut<UserRegistry>(owner_addr);
        let idx_opt = common_utils::index_of_addr(&reg.users, user_addr);
        assert!(option::is_some(&idx_opt), 6);
        let idx = option::extract(idx_opt);
        let (_, mut data) = *common_utils::borrow_by_index(&reg.users, idx);
        common_utils::remove_by_index(&mut reg.users, idx);
        data.active = active;
        vector::push_back(&mut reg.users, (user_addr, data));
    }

    /// Credit user internal numeric balance (called by admin or spend manager)
    public entry fun credit_user_balance(reg_owner: &signer, user_addr: address, amount: u128) acquires UserRegistry {
        let owner_addr = signer::address_of(reg_owner);
        assert!(exists<UserRegistry>(owner_addr), 7);
        let reg = borrow_global_mut<UserRegistry>(owner_addr);
        let idx_opt = common_utils::index_of_addr(&reg.users, user_addr);
        assert!(option::is_some(&idx_opt), 8);
        let idx = option::extract(idx_opt);
        let (_, mut data) = *common_utils::borrow_by_index(&reg.users, idx);
        common_utils::remove_by_index(&mut reg.users, idx);
        data.wallet_balance = data.wallet_balance + amount;
        vector::push_back(&mut reg.users, (user_addr, data));
    }

    /// Debit user numeric balance
    public entry fun debit_user_balance(reg_owner: &signer, user_addr: address, amount: u128) acquires UserRegistry {
        let owner_addr = signer::address_of(reg_owner);
        assert!(exists<UserRegistry>(owner_addr), 9);
        let reg = borrow_global_mut<UserRegistry>(owner_addr);
        let idx_opt = common_utils::index_of_addr(&reg.users, user_addr);
        assert!(option::is_some(&idx_opt), 10);
        let idx = option::extract(idx_opt);
        let (_, mut data) = *common_utils::borrow_by_index(&reg.users, idx);
        common_utils::remove_by_index(&mut reg.users, idx);
        assert!(data.wallet_balance >= amount, 11);
        data.wallet_balance = data.wallet_balance - amount;
        vector::push_back(&mut reg.users, (user_addr, data));
    }

    /// Query user wallet numeric balance
    public fun get_user_balance(reg_owner: address, user_addr: address): u128 acquires UserRegistry {
        assert!(exists<UserRegistry>(reg_owner), 12);
        let reg = borrow_global<UserRegistry>(reg_owner);
        let idx_opt = common_utils::index_of_addr(&reg.users, user_addr);
        assert!(option::is_some(&idx_opt), 13);
        let idx = option::extract(idx_opt);
        let (_, data) = *common_utils::borrow_by_index(&reg.users, idx);
        data.wallet_balance
    }

    // Note: helper to make compile-time simpler if you want to implement find_registry_owner:
    native fun find_registry_owner(): address;
}
