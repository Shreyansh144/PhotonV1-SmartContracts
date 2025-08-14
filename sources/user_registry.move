module photon_user_module_deployer::PhotonUsersModule {
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
    use std::string::{String, utf8};
    use pat_token_deployer::pat_coin::{ Self, get_metadata,transfer,balance};


    const PHOTON_ADMIN: address = @photon_admin;


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
        user_metadata: String,         // metadata URI or hash as bytes
        identity_hash: String,         // SHA256 hash of email (as bytes)
        created_at: u64,                   // unix timestamp
        active: bool,                      // active flag
        total_tokens_earned_by_campaign: u128,
        client_id: u64
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
        user: &signer,
        metadata: String,
        identity_hash: String,
        client_id: u64
    ) {
        // Only admin may register
        let user_address = signer::address_of(user);
        
        // Check if user is already registered
        if (is_user_registered(user_address)) {
            abort E_ALREADY_REGISTERED;
        };
        
        // Create user registry at the user's address
        let now = timestamp::now_seconds();
        
        move_to(user, UserRegistry {
            user_metadata: metadata,
            identity_hash: identity_hash,
            created_at: now,
            active: true,
            total_tokens_earned_by_campaign: 0,
            client_id: client_id
        });
    }

    // ====== View user ======
    public fun get_user(user_address: address): UserRegistry acquires UserRegistry {
        // admin-only view for now
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

    // ====== Convenience: check if registered ======
    public fun is_registered(user_address: address): bool {
        is_user_registered(user_address)
    }

    // ====== Initialize admin ======
    public entry fun initialize_admin(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        if (PHOTON_ADMIN != admin_addr) {
            abort E_NOT_ADMIN;
        };
        if (!exists<Admin>(admin_addr)) {
            move_to(admin, Admin { owner: admin_addr })
        };
    }

    // ====== Get user wallet balance ======
    #[view]
    public fun get_user_balance(user_address: address): u64 {
        if (!exists<UserRegistry>(user_address)) {
            abort E_NOT_REGISTERED;
        };
        let val = balance(user_address);  // Changed from admin_addr to user_address
        val
    }
}
