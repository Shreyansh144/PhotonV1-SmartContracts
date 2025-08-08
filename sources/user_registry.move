module 0x1::user_registry {
    use std::signer;
    use std::vector;
    use std::string;
    use std::option;
    use std::error;
    use std::address;
    use std::timestamp;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::managed_coin;

    // ====== ERROR CODES ======
    const E_NOT_ADMIN: u64 = 1;
    const E_ALREADY_REGISTERED: u64 = 2;
    const E_NOT_REGISTERED: u64 = 3;
    const E_INSUFFICIENT_BALANCE: u64 = 4;
    const E_INVALID_USER_TYPE: u64 = 5;
    const E_INSUFFICIENT_FUND: u64 = 6;
    const E_USER_MISMATCH: u64 = 7;

    // ====== USER TYPE ENUM (represented as u8) ======
    // 0 = Unknown
    // 1 = Individual
    // 2 = Business
    // 3 = VIP
    // 4 = Premium
    const USER_TYPE_UNKNOWN: u8 = 0;
    const USER_TYPE_INDIVIDUAL: u8 = 1;
    const USER_TYPE_BUSINESS: u8 = 2;
    const USER_TYPE_VIP: u8 = 3;
    const USER_TYPE_PREMIUM: u8 = 4;

    // ====== Admin resource ======
    struct Admin has key {
        owner: address,
    }

    // ====== User resource stored at resource account ======
    struct UserRegistry has key, store {
        user_name: vector<u8>,             // name bytes
        user_metadata: vector<u8>,         // metadata URI or hash as bytes
        user_wallet_address: address,      // on-chain address for the user's Aptos wallet
        identity_hash: vector<u8>,         // SHA256 hash of email (as bytes)
        created_at: u64,                   // unix timestamp
        active: bool,                      // active flag
        coin_type: address,                // address of PAT token module / coin marker (informational)
        total_tokens_earned: u128,
        total_tokens_spent: u128,
        user_type: u8,                     // enum value
        is_kyc_verified: bool,
        wallet_balance: u128,              // internal numeric balance
        signer_cap: account::SignerCapability, // Resource account signer capability
    }

    // Map to store user seeds and corresponding resource account address
    struct UserCap has key {
        userMap: SimpleMap<vector<u8>, address>,
        isProtocol: SimpleMap<address, bool>,
    }

    // ====== Helpers ======
    fun assert_admin(caller: &signer) {
        let owner_addr = signer::address_of(caller);
        let admin_ref = borrow_global<Admin>(owner_addr);
        if (admin_ref.owner != owner_addr) {
            abort E_NOT_ADMIN;
        }
    }

    // ====== Register user with resource account ======
    public entry fun register_user(
        admin: &signer,
        name: vector<u8>,
        metadata: vector<u8>,
        identity_hash: vector<u8>,
        user_type: u8,
        seeds: vector<u8>,
        isProtocol: bool
    ) acquires UserCap {
        // Only admin may register
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        
        // Create resource account for the user
        let (user_account, user_cap) = account::create_resource_account(admin, seeds);
        let user_address = signer::address_of(&user_account);
        
        // Initialize UserCap if it doesn't exist
        if (!exists<UserCap>(admin_addr)) {
            move_to(admin, UserCap { 
                userMap: simple_map::create(),
                isProtocol: simple_map::create()
            })
        };
        
        // Store the mapping of seeds to resource account address
        let maps = borrow_global_mut<UserCap>(admin_addr);
        simple_map::add(&mut maps.userMap, seeds, user_address);
        simple_map::add(&mut maps.isProtocol, user_address, isProtocol);
        
        // Create user registry at the resource account
        let user_signer_from_cap = account::create_signer_with_capability(&user_cap);
        let now = timestamp::now_seconds();
        
        move_to(&user_signer_from_cap, UserRegistry {
            user_name: name,
            user_metadata: metadata,
            user_wallet_address: user_address,
            identity_hash: identity_hash,
            created_at: now,
            active: true,
            coin_type: @0x1, // Default coin type address, can be updated later
            total_tokens_earned: 0,
            total_tokens_spent: 0,
            user_type: user_type,
            is_kyc_verified: false,
            wallet_balance: 0,
            signer_cap: user_cap,
        });
    }

    // ====== View user ======
    public fun get_user(admin: &signer, user_seeds: vector<u8>): UserRegistry acquires UserCap {
        // admin-only view for now
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        let user_addr_opt = simple_map::get(&maps.userMap, &user_seeds);
        if (!option::is_some(&user_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let user_addr = option::extract(&mut user_addr_opt);
        *borrow_global<UserRegistry>(user_addr)
    }

    // ====== Update simple flags & metadata ======
    public entry fun set_active(admin: &signer, user_seeds: vector<u8>, active: bool) acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        let user_addr_opt = simple_map::get(&maps.userMap, &user_seeds);
        if (!option::is_some(&user_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let user_addr = option::extract(&mut user_addr_opt);
        let user_ref = borrow_global_mut<UserRegistry>(user_addr);
        user_ref.active = active;
    }

    public entry fun set_kyc(admin: &signer, user_seeds: vector<u8>, verified: bool) acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        let user_addr_opt = simple_map::get(&maps.userMap, &user_seeds);
        if (!option::is_some(&user_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let user_addr = option::extract(&mut user_addr_opt);
        let user_ref = borrow_global_mut<UserRegistry>(user_addr);
        user_ref.is_kyc_verified = verified;
    }

    // ====== Token accounting helpers (admin-triggered) ======
    // Credit earned tokens to a user (tracked only numerically here)
    public entry fun credit_tokens(admin: &signer, user_seeds: vector<u8>, amount: u128) acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        let user_addr_opt = simple_map::get(&maps.userMap, &user_seeds);
        if (!option::is_some(&user_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let user_addr = option::extract(&mut user_addr_opt);
        let user_ref = borrow_global_mut<UserRegistry>(user_addr);
        user_ref.total_tokens_earned = user_ref.total_tokens_earned + amount;
        user_ref.wallet_balance = user_ref.wallet_balance + amount;
        //needs to add transfer tokens from admin via pat_coin
    }

    // Debit tokens when user spends
    public entry fun debit_tokens(admin: &signer, user_seeds: vector<u8>, amount: u128) acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        let user_addr_opt = simple_map::get(&maps.userMap, &user_seeds);
        if (!option::is_some(&user_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let user_addr = option::extract(&mut user_addr_opt);
        let user_ref = borrow_global_mut<UserRegistry>(user_addr);
        if (user_ref.wallet_balance < amount) {
            abort E_INSUFFICIENT_BALANCE;
        };
        user_ref.total_tokens_spent = user_ref.total_tokens_spent + amount;
        user_ref.wallet_balance = user_ref.wallet_balance - amount;
    }

    // ====== Convenience: check if registered ======
    public fun is_registered(admin: &signer, user_seeds: vector<u8>): bool acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        simple_map::contains_key(&maps.userMap, &user_seeds)
    }

    // ====== Remove user (admin only) ======
    public entry fun remove_user(admin: &signer, user_seeds: vector<u8>) acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global_mut<UserCap>(admin_addr);
        
        if (!simple_map::contains_key(&maps.userMap, &user_seeds)) {
            abort E_NOT_REGISTERED;
        };
        
        let user_addr = simple_map::remove(&mut maps.userMap, &user_seeds);
        simple_map::remove(&mut maps.isProtocol, &user_addr);
        
        // Extract and destroy the user registry
        let UserRegistry {
            user_name: _,
            user_metadata: _,
            user_wallet_address: _,
            identity_hash: _,
            created_at: _,
            active: _,
            coin_type: _,
            total_tokens_earned: _,
            total_tokens_spent: _,
            user_type: _,
            is_kyc_verified: _,
            wallet_balance: _,
            signer_cap: _,
        } = move_from<UserRegistry>(user_addr);
    }

    // ====== Initialize admin ======
    public entry fun initialize_admin(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        if (!exists<Admin>(admin_addr)) {
            move_to(admin, Admin { owner: admin_addr })
        };
    }

    // ====== Get user resource account address ======
    public fun get_user_resource_address(admin: &signer, user_seeds: vector<u8>): address acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        let user_addr_opt = simple_map::get(&maps.userMap, &user_seeds);
        if (!option::is_some(&user_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        option::extract(&mut user_addr_opt)
    }

    // ====== Check if user is protocol ======
    public fun is_protocol_user(admin: &signer, user_seeds: vector<u8>): bool acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        let user_addr_opt = simple_map::get(&maps.userMap, &user_seeds);
        if (!option::is_some(&user_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let user_addr = option::extract(&mut user_addr_opt);
        simple_map::contains_key(&maps.isProtocol, &user_addr) && 
        *simple_map::borrow(&maps.isProtocol, &user_addr)
    }

    // ====== Get user wallet balance ======
    public fun get_user_balance(admin: &signer, user_seeds: vector<u8>): u128 acquires UserCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<UserCap>(admin_addr);
        let user_addr_opt = simple_map::get(&maps.userMap, &user_seeds);
        if (!option::is_some(&user_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let user_addr = option::extract(&mut user_addr_opt);
        let user_ref = borrow_global<UserRegistry>(user_addr);
        user_ref.wallet_balance
    }
}
