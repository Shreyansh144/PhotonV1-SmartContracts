// module photon_admin_deployer::PhotonAdmin {
//     use std::signer;
//     use std::vector;
//     use aptos_framework::account;
//     use aptos_framework::resource_account;
//     use std::error;
//     use aptos_framework::primary_fungible_store;
//     use pat_token_deployer::pat_coin::{ Self, get_metadata,transfer,balance};


//     const DEV: address = @photon_dev;
//     const ZERO_ACCOUNT: address = @zero;
//     const PHOTON_ADMIN: address = @photon_admin;

//     const ERROR_NOT_ADMIN: u64 = 0;
//     const ERROR_INVALID_PERCENT: u64 = 1;
//     const ERROR_INVALID_ADDRESS: u64 = 2;
//     const E_OWNER_NOT_INITIALIZED: u64 = 3;
//     const E_INVALID_OWNER: u64 = 4;
//     const E_ADMIN_RESOURCE_NOT_INITIALIZED: u64 = 5;
//     const E_INVALID_AMOUNT: u64 = 6;
//     const E_ADMIN_NOT_HAVING_ENOUGH_COIN: u64 = 7;
//     const E_ADMIN_MANAGER_NOT_HAVING_ENOUGH_COIN: u64 = 8;

//         // ====== Admin resource ======
//     struct AdminPanel has key,store {
//         owner: address,
//         admin_manager_address: address,
//         whitelisted_processors: vector<address>,
//         params: SetPlatformFeeParams,
//     }
//     struct SetPlatformFeeParams has copy, store {
//         platform_spend_fee_percent: u8,
//         platform_earn_fee_percent: u8
//     }
    
//     // ====== Helpers ======
//     fun assert_admin(caller: &signer) acquires AdminPanel {
//         let owner_addr = signer::address_of(caller);
//         let admin_ref = borrow_global<AdminPanel>(owner_addr);
//         if (admin_ref.owner != owner_addr) {
//             abort ERROR_NOT_ADMIN;
//         }
//     }

//     struct Capabilities has key {
//         admin_signer_cap: account::SignerCapability, // Resource account signer capability
//     }


//     public entry fun init_admin(admin: &signer) {
//         let admin_addr = signer::address_of(admin);
//         assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));
//         let (admin_manager, admin_cap) = account::create_resource_account(admin, b"admin_test_3");
//         let admin_resource_addr = signer::address_of(&admin_manager);
//         let admin_signer_from_cap = account::create_signer_with_capability(&admin_cap);

//         let whitelisted_processors = vector[@processors1, @processors2, @processors3];
//         let params = SetPlatformFeeParams {
//             platform_spend_fee_percent: 0,
//             platform_earn_fee_percent: 0
//         };

//         move_to(&admin_signer_from_cap, Capabilities {
//             admin_signer_cap: admin_cap
//         });
//         move_to(admin, AdminPanel { 
//             whitelisted_processors,
//             params: params,
//             owner: admin_addr,
//             admin_manager_address: admin_resource_addr,
//         });
//         primary_fungible_store::ensure_primary_store_exists(admin_addr, get_metadata());
//     }

//     public entry fun credit_admin_manager_wallet(admin: &signer, amount: u128) acquires AdminPanel{
//         assert_admin(admin);

//         let admin_addr = signer::address_of(admin);
//         let admin_resource_addr = get_admin_resource_address();

//         if (!exists<Capabilities>(admin_resource_addr)) { 
//             abort E_ADMIN_RESOURCE_NOT_INITIALIZED;
//         };
        
//         if (amount == 0) {
//             abort E_INVALID_AMOUNT;
//         };

//         assert!(balance(admin_addr) >= (amount as u64), error::invalid_argument(E_ADMIN_NOT_HAVING_ENOUGH_COIN));

//         primary_fungible_store::ensure_primary_store_exists(admin_resource_addr, get_metadata());
//         transfer(admin, admin_resource_addr, (amount as u64));
//     }

//     public entry fun debit_admin_manager_wallet(user: &signer, amount: u128) acquires AdminPanel, Capabilities {
        
//         let user_addr = signer::address_of(user);
//         let admin_resource_addr = get_admin_resource_address();

//         if (!exists<Capabilities>(admin_resource_addr)) { 
//             abort E_ADMIN_RESOURCE_NOT_INITIALIZED;
//         };
        
//         if (amount == 0) {
//             abort E_INVALID_AMOUNT;
//         };

//         assert!(balance(admin_resource_addr) >= (amount as u64), error::invalid_argument(E_ADMIN_MANAGER_NOT_HAVING_ENOUGH_COIN));

//         let admin_resource_data = borrow_global_mut<Capabilities>(admin_resource_addr);
//         let admin_signer_from_cap = account::create_signer_with_capability(&admin_resource_data.admin_signer_cap);

//         primary_fungible_store::ensure_primary_store_exists(user_addr, get_metadata());
//         transfer(&admin_signer_from_cap, user_addr, (amount as u64));
//     }

//     public entry fun add_whitelisted_processor(admin: &signer, new_processor: address) acquires AdminPanel {
//         let panel = borrow_global_mut<AdminPanel>(PHOTON_ADMIN);

//         assert!(signer::address_of(admin) == panel.owner, ERROR_NOT_ADMIN);
//         assert!(new_processor != ZERO_ACCOUNT, ERROR_INVALID_ADDRESS);

//         if (vector::contains(&panel.whitelisted_processors, &new_processor)) {
//             return;
//         };
//         vector::push_back(&mut panel.whitelisted_processors, new_processor);
//     }

//     public entry fun change_fee_params(
//         admin: &signer,
//         platform_spend_fee_percent: u8,
//         platform_earn_fee_percent: u8
//     ) acquires AdminPanel {
//         let panel = borrow_global_mut<AdminPanel>(PHOTON_ADMIN);

//         assert!(signer::address_of(admin) == panel.owner, ERROR_NOT_ADMIN);
//         assert!(platform_spend_fee_percent <= 100 && platform_earn_fee_percent <= 100, ERROR_INVALID_PERCENT);

//         panel.params.platform_spend_fee_percent = platform_spend_fee_percent;
//         panel.params.platform_earn_fee_percent = platform_earn_fee_percent;
//     }

//         /// Function to get merchant_manager_address from AdminStore
//     public fun get_admin_resource_address(): address acquires AdminPanel{
//         if (!exists<AdminPanel>(PHOTON_ADMIN)) {
//             abort E_OWNER_NOT_INITIALIZED;
//         };

//         let admin_store_data = borrow_global<AdminPanel>(PHOTON_ADMIN);
//         let admin_addr = admin_store_data.admin_manager_address;
//         admin_addr
//     }

// }
