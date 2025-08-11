// module 0x1::user_registry {
//     use std::signer;
//     use std::vector;
//     use std::string;
//     use std::option;
//     use std::error;
//     use std::address;
//     use std::timestamp;
//     use aptos_std::simple_map::{Self, SimpleMap};
//     use aptos_framework::account;
//     use aptos_framework::coin::{Self, Coin};
//     use aptos_framework::managed_coin;

//     // ====== ERROR CODES ======
//     const E_NOT_ADMIN: u64 = 1;
//     const E_ALREADY_REGISTERED: u64 = 2;
//     const E_NOT_REGISTERED: u64 = 3;
//     const E_INSUFFICIENT_BALANCE: u64 = 4;
//     const E_INVALID_USER_TYPE: u64 = 5;
//     const E_INSUFFICIENT_FUND: u64 = 6;
//     const E_USER_MISMATCH: u64 = 7;

//     // ====== USER TYPE ENUM (represented as u8) ======
//     // 0 = Unknown
//     // 1 = Individual
//     // 2 = Business
//     // 3 = VIP
//     // 4 = Premium
//     const USER_TYPE_UNKNOWN: u8 = 0;
//     const USER_TYPE_INDIVIDUAL: u8 = 1;
//     const USER_TYPE_BUSINESS: u8 = 2;
//     const USER_TYPE_VIP: u8 = 3;
//     const USER_TYPE_PREMIUM: u8 = 4;

//     // ====== Admin resource ======
//     struct Admin has key {
//         owner: address,
//     }

//     // ====== User resource stored at user's address ======
//     struct UserRegistry has key, store {
//         user_name: vector<u8>,             // name bytes
//         user_metadata: vector<u8>,         // metadata URI or hash as bytes
//         user_wallet_address: address,      // on-chain address for the user's Aptos wallet
//         identity_hash: vector<u8>,         // SHA256 hash of email (as bytes)
//         created_at: u64,                   // unix timestamp
//         active: bool,                      // active flag
//         coin_type: address,                // address of PAT token module / coin marker (informational)
//         total_tokens_earned: u128,
//         total_tokens_spent: u128,
//         user_type: u8,                     // enum value
//         is_kyc_verified: bool,
//         wallet_balance: u128,              // internal numeric balance
//         signer_cap: account::SignerCapability, // Resource account signer capability
//     }

//     // Simple storage for registered user addresses
//     struct UserCap has key {
//         registered_users: vector<address>,
//     }

//     // ====== Helpers ======
//     fun assert_admin(caller: &signer) {
//         let owner_addr = signer::address_of(caller);
//         let admin_ref = borrow_global<Admin>(owner_addr);
//         if (admin_ref.owner != owner_addr) {
//             abort E_NOT_ADMIN;
//         }
//     }

//     fun is_user_registered(user_addr: address): bool acquires UserCap {
//         let user_cap = borrow_global<UserCap>(@0x1);
//         let i = 0;
//         let len = vector::length(&user_cap.registered_users);
//         while (i < len) {
//             if (vector::borrow(&user_cap.registered_users, i) == &user_addr) {
//                 return true
//             };
//             i = i + 1;
//         };
//         false
//     }

//     // ====== Register user ======
//     public entry fun register_user(
//         admin: &signer,
//         user_address: address,
//         name: vector<u8>,
//         metadata: vector<u8>,
//         identity_hash: vector<u8>,
//         user_type: u8,
//         isProtocol: bool
//     ) acquires UserCap {
//         // Only admin may register
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         // Initialize UserCap if it doesn't exist
//         if (!exists<UserCap>(@0x1)) {
//             move_to(admin, UserCap { 
//                 registered_users: vector::empty()
//             })
//         };
        
//         // Check if user is already registered
//         if (is_user_registered(user_address)) {
//             abort E_ALREADY_REGISTERED;
//         };
        
//         // Add user address to registered users list
//         let user_cap = borrow_global_mut<UserCap>(@0x1);
//         vector::push_back(&mut user_cap.registered_users, user_address);
        
//         // Create user registry at the user's address
//         let now = timestamp::now_seconds();
        
//         move_to(admin, UserRegistry {
//             user_name: name,
//             user_metadata: metadata,
//             user_wallet_address: user_address,
//             identity_hash: identity_hash,
//             created_at: now,
//             active: true,
//             coin_type: @0x1, // Default coin type address, can be updated later
//             total_tokens_earned: 0,
//             total_tokens_spent: 0,
//             user_type: user_type,
//             is_kyc_verified: false,
//             wallet_balance: 0,
//             is_protocol: isProtocol,
//         });
//     }

//     // ====== View user ======
//     public fun get_user(admin: &signer, user_address: address): UserRegistry {
//         // admin-only view for now
//         assert_admin(admin);
//         if (!exists<UserRegistry>(user_address)) {
//             abort E_NOT_REGISTERED;
//         };
//         *borrow_global<UserRegistry>(user_address)
//     }

//     // ====== Update simple flags & metadata ======
//     public entry fun set_active(admin: &signer, user_address: address, active: bool) {
//         assert_admin(admin);
//         if (!exists<UserRegistry>(user_address)) {
//             abort E_NOT_REGISTERED;
//         };
//         let user_ref = borrow_global_mut<UserRegistry>(user_address);
//         user_ref.active = active;
//     }

//     public entry fun set_kyc(admin: &signer, user_address: address, verified: bool) {
//         assert_admin(admin);
//         if (!exists<UserRegistry>(user_address)) {
//             abort E_NOT_REGISTERED;
//         };
//         let user_ref = borrow_global_mut<UserRegistry>(user_address);
//         user_ref.is_kyc_verified = verified;
//     }

//     // ====== Token accounting helpers (admin-triggered) ======
//     // Credit earned tokens to a user (tracked only numerically here)
//     public entry fun credit_tokens(admin: &signer, user_address: address, amount: u128) {
//         assert_admin(admin);
//         if (!exists<UserRegistry>(user_address)) {
//             abort E_NOT_REGISTERED;
//         };
//         let user_ref = borrow_global_mut<UserRegistry>(user_address);
//         user_ref.total_tokens_earned = user_ref.total_tokens_earned + amount;
//         user_ref.wallet_balance = user_ref.wallet_balance + amount;
//         //needs to add transfer tokens from admin via pat_coin
//     }

//     // Debit tokens when user spends
//     public entry fun debit_tokens(admin: &signer, user_address: address, amount: u128) {
//         assert_admin(admin);
//         if (!exists<UserRegistry>(user_address)) {
//             abort E_NOT_REGISTERED;
//         };
//         let user_ref = borrow_global_mut<UserRegistry>(user_address);
//         if (user_ref.wallet_balance < amount) {
//             abort E_INSUFFICIENT_BALANCE;
//         };
//         user_ref.total_tokens_spent = user_ref.total_tokens_spent + amount;
//         user_ref.wallet_balance = user_ref.wallet_balance - amount;
//     }

//     // ====== Convenience: check if registered ======
//     public fun is_registered(admin: &signer, user_address: address): bool acquires UserCap {
//         assert_admin(admin);
//         is_user_registered(user_address)
//     }

//     // ====== Remove user (admin only) ======
//     public entry fun remove_user(admin: &signer, user_address: address) acquires UserCap {
//         assert_admin(admin);
        
//         if (!is_user_registered(user_address)) {
//             abort E_NOT_REGISTERED;
//         };
        
//         // Remove from registered users list
//         let user_cap = borrow_global_mut<UserCap>(@0x1);
//         let i = 0;
//         let len = vector::length(&user_cap.registered_users);
//         while (i < len) {
//             if (vector::borrow(&user_cap.registered_users, i) == &user_address) {
//                 vector::remove(&mut user_cap.registered_users, i);
//                 break
//             };
//             i = i + 1;
//         };
        
//         // Extract and destroy the user registry
//         let UserRegistry {
//             user_name: _,
//             user_metadata: _,
//             user_wallet_address: _,
//             identity_hash: _,
//             created_at: _,
//             active: _,
//             coin_type: _,
//             total_tokens_earned: _,
//             total_tokens_spent: _,
//             user_type: _,
//             is_kyc_verified: _,
//             wallet_balance: _,
//             is_protocol: _,
//         } = move_from<UserRegistry>(user_address);
//     }

//     // ====== Initialize admin ======
//     public entry fun initialize_admin(admin: &signer) {
//         let admin_addr = signer::address_of(admin);
//         if (!exists<Admin>(admin_addr)) {
//             move_to(admin, Admin { owner: admin_addr })
//         };
//     }

//     // ====== Check if user is protocol ======
//     public fun is_protocol_user(admin: &signer, user_address: address): bool {
//         assert_admin(admin);
//         if (!exists<UserRegistry>(user_address)) {
//             abort E_NOT_REGISTERED;
//         };
//         let user_ref = borrow_global<UserRegistry>(user_address);
//         user_ref.is_protocol
//     }

//     // ====== Get user wallet balance ======
//     public fun get_user_balance(admin: &signer, user_address: address): u128 {
//         assert_admin(admin);
//         if (!exists<UserRegistry>(user_address)) {
//             abort E_NOT_REGISTERED;
//         };
//         let user_ref = borrow_global<UserRegistry>(user_address);
//         user_ref.wallet_balance
//     }

//     // ====== Get all registered users ======
//     public fun get_registered_users(admin: &signer): vector<address> acquires UserCap {
//         assert_admin(admin);
//         let user_cap = borrow_global<UserCap>(@0x1);
//         *&user_cap.registered_users
//     }
// }
