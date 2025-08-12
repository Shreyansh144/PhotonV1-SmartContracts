// module photon_merchant_deployer::PhotonMerchantManagerModule {
//     use std::signer;
//     use std::timestamp;
//     use std::vector;
//     use std::error;
//     use aptos_framework::account;

//     // ====== ERROR CODES ======
//     const E_NOT_ADMIN: u64 = 1;
//     const E_NOT_REGISTERED: u64 = 2;
//     const E_INSUFFICIENT_BALANCE: u64 = 3;
//     const E_ALREADY_EXISTS: u64 = 4;
//     const E_NOT_INITIALIZED: u64 = 5;
//     const E_INVALID_AMOUNT: u64 = 6;

//     const PHOTON_ADMIN: address = @photon_admin;

//     // ====== Admin resource ======
//     struct Admin has key {
//         owner: address,
//     }

    

//     // ====== Merchant resource stored at admin address ======
//     struct MerchantStoreManager has key, store {
//         merchant_total_wallet_balance: u128, // numeric pool that holds PAT for merchant operations
//         merchant_signer_cap: account::SignerCapability, // Resource account signer capability
//         registered_merchants: vector<address>, // list of registered merchant addresses
//         merchant_balances: vector<u128>, // corresponding balances for each merchant
//         created_at: u64, // timestamp when manager was created
//         active: bool, // whether the merchant manager is active
//     }

//     // ====== Helpers ======
//     fun assert_admin(caller: &signer) acquires Admin {
//         let owner_addr = signer::address_of(caller);
//         let admin_ref = borrow_global<Admin>(owner_addr);
//         if (admin_ref.owner != owner_addr) {
//             abort E_NOT_ADMIN;
//         }
//     }

//     // Check if merchant is registered
//     fun is_merchant_registered(merchant_addr: address, manager: &MerchantStoreManager): bool {
//         let i = 0;
//         let len = vector::length(&manager.registered_merchants);
//         while (i < len) {
//             if (vector::borrow(&manager.registered_merchants, i) == &merchant_addr) {
//                 return true
//             };
//             i = i + 1;
//         };
//         false
//     }

//     // Get merchant index in the registered merchants list
//     fun get_merchant_index(merchant_addr: address, manager: &MerchantStoreManager): u64 {
//         let i = 0;
//         let len = vector::length(&manager.registered_merchants);
//         while (i < len) {
//             if (vector::borrow(&manager.registered_merchants, i) == &merchant_addr) {
//                 return i
//             };
//             i = i + 1;
//         };
//         abort E_NOT_REGISTERED
//     }

//     // ====== Initialize admin and merchant manager ======
//     public entry fun initialize_admin(admin: &signer) {
//         let admin_addr = signer::address_of(admin);
//         if (!exists<Admin>(admin_addr)) {
//             move_to(admin, Admin { owner: admin_addr })
//         };
//     }

//     public entry fun initialize_merchant_manager(admin: &signer) acquires Admin {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         if (!exists<MerchantStoreManager>(admin_addr)) {
//             // Create resource account for merchant management
//             let (merchant_account, merchant_cap) = account::create_resource_account(admin, b"merchant_manager");
            
//             move_to(admin, MerchantStoreManager {
//                 merchant_total_wallet_balance: 0,
//                 merchant_signer_cap: merchant_cap,
//                 registered_merchants: vector::empty(),
//                 merchant_balances: vector::empty(),
//                 created_at: timestamp::now_seconds(),
//                 active: true,
//             });
//         };
//     }

//     // ====== Register new merchant ======
//     public entry fun register_merchant(admin: &signer, merchant_address: address) acquires Admin, MerchantStoreManager {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         if (!exists<MerchantStoreManager>(admin_addr)) {
//             abort E_NOT_INITIALIZED;
//         };
        
//         let manager = borrow_global_mut<MerchantStoreManager>(admin_addr);
        
//         // Check if merchant is already registered
//         if (is_merchant_registered(merchant_address, manager)) {
//             return; // Already registered
//         };
        
//         // Add merchant to the list
//         vector::push_back(&mut manager.registered_merchants, merchant_address);
//         vector::push_back(&mut manager.merchant_balances, 0);
//     }

//     // ====== Credit merchant wallet ======
//     public entry fun credit_merchant_wallet(signer: &signer, merchant_address: address, amount: u128) 
//         acquires  MerchantStoreManager {
//         let signer_addr = signer::address_of(signer);
        
//         if (!exists<MerchantStoreManager>(signer_addr)) {
//             abort E_NOT_INITIALIZED;
//         };
        
//         if (amount == 0) {
//             abort E_INVALID_AMOUNT;
//         };
        
//         let manager = borrow_global_mut<MerchantStoreManager>(PHOTON_ADMIN);
        
//         if (!is_merchant_registered(merchant_address, manager)) {
//             abort E_NOT_REGISTERED;
//         };
        
//         let merchant_index = get_merchant_index(merchant_address, manager);
//         let merchant_balance = vector::borrow_mut(&mut manager.merchant_balances, merchant_index);
//         *merchant_balance = *merchant_balance + amount;
        
//         // Update total manager balance
//         manager.merchant_total_wallet_balance = manager.merchant_total_wallet_balance + amount;
//     }

//     // ====== Withdraw all merchant balances (settlement) ======
//     public entry fun withdraw_all_merchant_balances(admin: &signer) acquires Admin, MerchantStoreManager {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);

//         if (!exists<MerchantStoreManager>(admin_addr)) {
//             abort E_NOT_INITIALIZED;
//         };

//         let manager = borrow_global_mut<MerchantStoreManager>(admin_addr);

//         let i = 0;
//         let len = vector::length(&manager.merchant_balances);
//         while (i < len) {
//             let bal_ref = vector::borrow_mut(&mut manager.merchant_balances, i);
//             *bal_ref = 0;
//             i = i + 1;
//         };

//         manager.merchant_total_wallet_balance = 0;
//     }

//     // ====== Get merchant balance ======
//     public fun get_merchant_balance(admin: &signer, merchant_address: address): u128 
//         acquires Admin, MerchantStoreManager {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         if (!exists<MerchantStoreManager>(admin_addr)) {
//             abort E_NOT_INITIALIZED;
//         };
        
//         let manager = borrow_global<MerchantStoreManager>(admin_addr);
        
//         if (!is_merchant_registered(merchant_address, manager)) {
//             abort E_NOT_REGISTERED;
//         };
        
//         let merchant_index = get_merchant_index(merchant_address, manager);
//         *vector::borrow(&manager.merchant_balances, merchant_index)
//     }

//     // ====== Get total manager balance ======
//     public fun get_total_manager_balance(admin: &signer): u128 acquires Admin, MerchantStoreManager {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         if (!exists<MerchantStoreManager>(admin_addr)) {
//             abort E_NOT_INITIALIZED;
//         };
        
//         let manager = borrow_global<MerchantStoreManager>(admin_addr);
//         manager.merchant_total_wallet_balance
//     }

//     // ====== Get registered merchants count ======
//     public fun get_registered_merchants_count(admin: &signer): u64 acquires Admin, MerchantStoreManager {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         if (!exists<MerchantStoreManager>(admin_addr)) {
//             abort E_NOT_INITIALIZED;
//         };
        
//         let manager = borrow_global<MerchantStoreManager>(admin_addr);
//         vector::length(&manager.registered_merchants)
//     }

//     // ====== Set merchant manager active status ======
//     public entry fun set_merchant_manager_active(admin: &signer, active: bool) acquires Admin, MerchantStoreManager {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         if (!exists<MerchantStoreManager>(admin_addr)) {
//             abort E_NOT_INITIALIZED;
//         };
        
//         let manager = borrow_global_mut<MerchantStoreManager>(admin_addr);
//         manager.active = active;
//     }

//     // ====== Remove merchant ======
//     public entry fun remove_merchant(admin: &signer, merchant_address: address) acquires Admin, MerchantStoreManager {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         if (!exists<MerchantStoreManager>(admin_addr)) {
//             abort E_NOT_INITIALIZED;
//         };
        
//         let manager = borrow_global_mut<MerchantStoreManager>(admin_addr);
        
//         if (!is_merchant_registered(merchant_address, manager)) {
//             abort E_NOT_REGISTERED;
//         };
        
//         let merchant_index = get_merchant_index(merchant_address, manager);
        
//         // Remove merchant and their balance
//         vector::remove(&mut manager.registered_merchants, merchant_index);
//         let merchant_balance = vector::remove(&mut manager.merchant_balances, merchant_index);
        
//         // Update total manager balance
//         manager.merchant_total_wallet_balance = manager.merchant_total_wallet_balance - merchant_balance;
//     }
// }
