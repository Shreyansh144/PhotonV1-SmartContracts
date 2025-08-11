module photon_admin::PhotonUserModule {
    use std::signer;
    use std::vector;
    use std::string;
    use std::option;
    use std::error;
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

    // ====== Admin resource ======
    struct Admin has key {
        owner: address,
    }

    // ====== User resource stored at user's address ======
    struct UserRegistry has key, store, copy {
        user_name: vector<u8>,             // name bytes
        user_metadata: vector<u8>,         // metadata URI or hash as bytes
        identity_hash: vector<u8>,         // SHA256 hash of email (as bytes)
        created_at: u64,                   // unix timestamp
        active: bool,                      // active flag
        // coin_type: address,                // Note: (if required) address of PAT token module / coin marker (informational)
        total_tokens_earned: u128,
        total_tokens_spent: u128,
        wallet_balance: u128
    }

    // ====== Helpers ======
    fun assert_admin(caller: &signer) acquires Admin {
        let owner_addr = signer::address_of(caller);
        let admin_ref = borrow_global<Admin>(owner_addr);
        if (admin_ref.owner != owner_addr) {
            abort E_NOT_ADMIN;
        }
    }

    // Check if user is registered by checking if UserRegistry exists at the address
    fun is_user_registered(user_addr: address): bool {
        exists<UserRegistry>(user_addr)
    }

    // ====== Register user ======
    public entry fun register_user(
        admin: &signer,
        user_address: address,
        name: vector<u8>,
        metadata: vector<u8>,
        identity_hash: vector<u8>,
    ) acquires Admin {
        // Only admin may register
        assert_admin(admin);
        
        // Check if user is already registered
        if (is_user_registered(user_address)) {
            abort E_ALREADY_REGISTERED;
        };
        
        // Create user registry at the user's address
        let now = timestamp::now_seconds();
        
        move_to(admin, UserRegistry {
            user_name: name,
            user_metadata: metadata,
            identity_hash: identity_hash,
            created_at: now,
            active: true,
            // coin_type: @photon_admin, // Default coin type address, can be updated later
            total_tokens_earned: 0,
            total_tokens_spent: 0,
            wallet_balance: 0,
        });
    }

    // ====== View user ======
    public fun get_user(admin: &signer, user_address: address): UserRegistry acquires Admin, UserRegistry {
        // admin-only view for now
        assert_admin(admin);
        if (!exists<UserRegistry>(user_address)) {
            abort E_NOT_REGISTERED;
        };
        *borrow_global<UserRegistry>(user_address)
    }

    // ====== Update simple flags & metadata ======
    public entry fun set_active(admin: &signer, user_address: address, active: bool) acquires Admin, UserRegistry {
        assert_admin(admin);
        if (!exists<UserRegistry>(user_address)) {
            abort E_NOT_REGISTERED;
        };
        let user_ref = borrow_global_mut<UserRegistry>(user_address);
        user_ref.active = active;
    }

    // ====== Token accounting helpers (admin-triggered) ======
    // Credit earned tokens to a user (tracked only numerically here)
    public entry fun credit_tokens(admin: &signer, user_address: address, amount: u128) acquires Admin, UserRegistry {
        assert_admin(admin);
        if (!exists<UserRegistry>(user_address)) {
            abort E_NOT_REGISTERED;
        };
        let user_ref = borrow_global_mut<UserRegistry>(user_address);
        user_ref.wallet_balance = user_ref.wallet_balance + amount;
        //needs to add transfer tokens from admin via pat_coin
    }

    // Debit tokens when user spends
    public entry fun debit_tokens(admin: &signer, user_address: address, amount: u128) acquires Admin, UserRegistry {
        assert_admin(admin);
        if (!exists<UserRegistry>(user_address)) {
            abort E_NOT_REGISTERED;
        };
        let user_ref = borrow_global_mut<UserRegistry>(user_address);
        if (user_ref.wallet_balance < amount) {
            abort E_INSUFFICIENT_BALANCE;
        };
        user_ref.wallet_balance = user_ref.wallet_balance - amount;
        //needs to add transfer tokens from user wallet via protocol/merchant
    }

    // ====== Convenience: check if registered ======
    public fun is_registered(admin: &signer, user_address: address): bool acquires Admin {
        assert_admin(admin);
        is_user_registered(user_address)
    }

    // ====== Initialize admin ======
    public entry fun initialize_admin(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        if (!exists<Admin>(admin_addr)) {
            move_to(admin, Admin { owner: admin_addr })
        };
    }

    // ====== Get user wallet balance ======
    public fun get_user_balance(admin: &signer, user_address: address): u128 acquires Admin, UserRegistry {
        assert_admin(admin);
        if (!exists<UserRegistry>(user_address)) {
            abort E_NOT_REGISTERED;
        };
        let user_ref = borrow_global<UserRegistry>(user_address);
        user_ref.wallet_balance
    }
}
