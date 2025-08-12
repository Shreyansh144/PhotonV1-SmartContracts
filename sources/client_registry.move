// module photon_client_deployer::PhotonClientModule {
//     use std::signer;
//     // use std::vector;
//     // use std::string;
//     use std::option;
//     use std::error;
//     use std::timestamp;
//     use aptos_std::simple_map::{Self, SimpleMap};
//     // use aptos_std::event::{Self, EventHandle};
//     use aptos_framework::account;
//     // use aptos_framework::coin::{Self, Coin};
//     // use aptos_framework::managed_coin;
//     use std::string::{String, utf8};



//     const PHOTON_ADMIN: address = @photon_admin;


//     // ====== ERROR CODES ======
//     const E_NOT_ADMIN: u64 = 1;
//     const E_ALREADY_REGISTERED: u64 = 2;
//     const E_NOT_REGISTERED: u64 = 3;
//     const E_INSUFFICIENT_BALANCE: u64 = 4;
//     const E_INVALID_CLIENT_TYPE: u64 = 5;
//     const E_INSUFFICIENT_FUND: u64 = 6;
//     const E_CLIENT_MISMATCH: u64 = 7;
//     const E_INVALID_OWNER: u64 = 8;
//     const E_OWNER_NOT_HAVING_ENOUGH_COIN: u64 = 9;

//     // ====== Admin resource ======
//     struct Admin has key {
//         owner: address,
//     }

//     // ====== Client resource stored at resource account ======
//     struct ClientRegistry has key, store, drop {
//         client_name: String,         // name bytes
//         client_metadata: String,     // metadata URI or hash as bytes
//         client_wallet_address: address,      // on-chain address for the client's Aptos wallet
//         created_at: u64,                 // unix timestamp
//         active: bool,                    // active flag
//         // coin_type: address,              // NOTE: (if required)address of PAT token module / coin marker (informational)
//         total_tokens_earned: u128,
//         total_tokens_spent: u128,
//         is_kyc_verified: bool,
//         local_earn_onboarding_fee_percent: u8,
//         local_spend_token_onboarding_client_fee_percent: u8,
//         local_spend_token_facilitator_client_fee_percent: u8,
//         signer_cap: account::SignerCapability, // Resource account signer capability
//     }

//     // Map to store client seeds and corresponding resource account address
//     struct ClientStore has key, copy, store {
//         clientMap: SimpleMap<vector<u8>, address>,
//         isProtocol: SimpleMap<address, bool>,
//         global_earn_onboarding_fee_percent: u8,
//         global_spend_token_onboarding_client_fee_percent: u8,
//         global_spend_token_facilitator_client_fee_percent: u8,
//     }

//     // ====== Helpers ======
//     fun assert_admin(caller: &signer)acquires Admin{
//         let owner_addr = signer::address_of(caller);
//         let admin_ref = borrow_global<Admin>(owner_addr);
//         if (admin_ref.owner != owner_addr) {
//             abort E_NOT_ADMIN;
//         }
//     }

//     // Resolve client address from seeds, aborting if not registered
//     fun get_client_address_or_abort(admin: &signer, client_seeds: &vector<u8>): address acquires ClientStore {
//         let admin_addr = signer::address_of(admin);
//         let maps = borrow_global<ClientStore>(admin_addr);
//         // This borrows the address from the map
//         *simple_map::borrow(&maps.clientMap, client_seeds)
//     }



//     // Removed functions that returned references to satisfy Move borrow checker.

//     // ====== Initialize admin and events ======
//     public entry fun initialize_client_store(admin: &signer) {
//         let admin_addr = signer::address_of(admin);
//         assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));

//         // // Create resource account for client registry management
//         // let (client_signer, client_cap) = account::create_resource_account(admin, b"client_registry");
//         // let client_signer_address = signer::address_of(&client_signer); //not required

//         if (!exists<ClientStore>(admin_addr)) {
//             move_to(admin, ClientStore { 
//                 clientMap: simple_map::create(),
//                 isProtocol: simple_map::create(),
//                 global_earn_onboarding_fee_percent: 0,
//                 global_spend_token_onboarding_client_fee_percent: 0,
//                 global_spend_token_facilitator_client_fee_percent: 0
//             });
//             move_to(admin, Admin { 
//                 owner: admin_addr
//             });
//         };
//     }

//     // ====== Register client with resource account ======
//     public entry fun register_client(
//         admin: &signer,
//         name: String,
//         metadata: String,
//         seeds: vector<u8>,
//         isProtocol: bool,
//         is_kyc_verified: bool
//     ) acquires Admin, ClientStore {
//         // Only admin may register
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         // Create resource account for the client
//         let (client_account, client_cap) = account::create_resource_account(admin, seeds);
//         let client_address = signer::address_of(&client_account);
        
//         // Initialize ClientStore if it doesn't exist
//         if (!exists<ClientStore>(admin_addr)) {
//             move_to(admin, ClientStore { 
//                 clientMap: simple_map::create(),
//                 isProtocol: simple_map::create(),
//                 global_earn_onboarding_fee_percent: 0,
//                 global_spend_token_onboarding_client_fee_percent: 0,
//                 global_spend_token_facilitator_client_fee_percent: 0,
//             });
//         };
        
//         // Store the mapping of seeds to resource account address
//         let maps = borrow_global_mut<ClientStore>(admin_addr);
//         simple_map::add(&mut maps.clientMap, seeds, client_address);
//         simple_map::add(&mut maps.isProtocol, client_address, isProtocol);
        
//         // Create client registry at the resource account
//         let client_signer_from_cap = account::create_signer_with_capability(&client_cap);
//         let now = timestamp::now_seconds();
        
//         move_to(&client_signer_from_cap, ClientRegistry {
//             client_name: name,
//             client_metadata: metadata,
//             client_wallet_address: client_address,
//             created_at: now,
//             active: true,
//             // coin_type: @PhotonResourceAddress, //Note: (if required) Default coin type address, can be updated later
//             total_tokens_earned: 0,
//             total_tokens_spent: 0,
//             is_kyc_verified: is_kyc_verified,
//             local_earn_onboarding_fee_percent: 0,
//             local_spend_token_onboarding_client_fee_percent: 0,
//             local_spend_token_facilitator_client_fee_percent: 0,
//             signer_cap: client_cap,
//         });
//     }

//     // ====== Update simple flags & metadata ======
//     public entry fun set_active(admin: &signer, client_seeds: vector<u8>, active: bool) acquires Admin, ClientStore, ClientRegistry {
//         assert_admin(admin);
//         let client_addr = get_client_address_or_abort(admin, &client_seeds);
//         let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
//         client_ref.active = active;
//     }

//     public entry fun set_kyc(admin: &signer, client_seeds: vector<u8>, verified: bool) acquires Admin, ClientStore, ClientRegistry {
//         assert_admin(admin);
//         let client_addr = get_client_address_or_abort(admin, &client_seeds);
//         let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
//         client_ref.is_kyc_verified = verified;
//     }

//     public entry fun set_local_fees(
//         admin: &signer,
//         client_seeds: vector<u8>,
//         earn_fee: u8,
//         spend_onboarding_fee: u8,
//         spend_facilitator_fee: u8
//     ) acquires Admin, ClientStore, ClientRegistry {
//         assert_admin(admin);
//         let client_addr = get_client_address_or_abort(admin, &client_seeds);
//         let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
//         // Optional: add range checks if needed (e.g., <= 100)
//         client_ref.local_earn_onboarding_fee_percent = earn_fee;
//         client_ref.local_spend_token_onboarding_client_fee_percent = spend_onboarding_fee;
//         client_ref.local_spend_token_facilitator_client_fee_percent = spend_facilitator_fee;
//     }

//     // ====== Token accounting helpers with coin transfer ======
//     // Credit earned tokens to a client with actual coin transfer
//     public entry fun credit_tokens<CoinType>(
//         admin: &signer, 
//         client_seeds: vector<u8>, 
//         amount: u128
//     ) acquires Admin, ClientStore, ClientRegistry {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
        
//         // Check admin has enough coins
//         // assert!(coin::balance<CoinType>(admin_addr) >= amount, error::invalid_argument(E_OWNER_NOT_HAVING_ENOUGH_COIN));
        
//         let client_addr = get_client_address_or_abort(admin, &client_seeds);
//         let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
        
//         // Transfer coins from admin to client resource account
//         // coin::transfer<CoinType>(admin, client_addr, amount);
        
//         // Update accounting
//         client_ref.total_tokens_earned = client_ref.total_tokens_earned + amount;
//     }

//     // Debit tokens when client spends (transfer back to admin)
//     public entry fun debit_tokens<CoinType>(
//         admin: &signer, 
//         client_seeds: vector<u8>, 
//         amount: u128
//     ) acquires Admin, ClientStore, ClientRegistry {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
//         let client_addr = get_client_address_or_abort(admin, &client_seeds);
//         let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
        
//         if (client_ref.total_tokens_earned < client_ref.total_tokens_spent + amount) {
//             abort E_INSUFFICIENT_BALANCE;
//         };

//         // Get client signer to transfer coins back to admin
//         let client_signer = account::create_signer_with_capability(&client_ref.signer_cap);
//         // coin::transfer<CoinType>(&client_signer, admin_addr, amount);
        
//         client_ref.total_tokens_spent = client_ref.total_tokens_spent + amount;
//     }

//     // ====== Convenience: check if registered ======
//     public fun is_registered(admin: &signer, client_seeds: vector<u8>): bool acquires Admin, ClientStore {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
//         let maps = borrow_global<ClientStore>(admin_addr);
//         simple_map::contains_key(&maps.clientMap, &client_seeds)
//     }

//     // ====== Remove client (admin only) ======
//     public entry fun remove_client(admin: &signer, client_seeds: vector<u8>) acquires Admin, ClientStore, ClientRegistry {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
//         let maps = borrow_global_mut<ClientStore>(admin_addr);

//         if (!simple_map::contains_key(&maps.clientMap, &client_seeds)) {
//             abort E_NOT_REGISTERED;
//         };

//         let (_, client_addr) = simple_map::remove(&mut maps.clientMap, &client_seeds);
//         if (simple_map::contains_key(&maps.isProtocol, &client_addr)) {
//             simple_map::remove(&mut maps.isProtocol, &client_addr);
//         };

//         let collection = move_from<ClientRegistry>(client_addr);
//         let ClientRegistry{
//             client_name: _,
//             client_metadata: _,
//             client_wallet_address: _,
//             created_at: _,
//             active: _,
//             total_tokens_earned: _,
//             total_tokens_spent: _,
//             is_kyc_verified: _,
//             local_earn_onboarding_fee_percent: _,
//             local_spend_token_onboarding_client_fee_percent: _,
//             local_spend_token_facilitator_client_fee_percent: _,
//             signer_cap: _
//         } = collection;
//     }


//     // ====== Get client resource account address ======
//     public fun get_client_resource_address(admin: &signer, client_seeds: vector<u8>): address acquires Admin, ClientStore {
//         assert_admin(admin);
//         get_client_address_or_abort(admin, &client_seeds)
//     }

//     // ====== Check if client is protocol ======
//     public fun is_protocol_client(admin: &signer, client_seeds: vector<u8>): bool acquires Admin, ClientStore {
//         assert_admin(admin);
//         let admin_addr = signer::address_of(admin);
//         let maps = borrow_global<ClientStore>(admin_addr);
//         if (!simple_map::contains_key(&maps.clientMap, &client_seeds)) {
//             abort E_NOT_REGISTERED;
//         };
//         let client_addr = *simple_map::borrow(&maps.clientMap, &client_seeds);
//         simple_map::contains_key(&maps.isProtocol, &client_addr) && *simple_map::borrow(&maps.isProtocol, &client_addr)
//     }

//     #[view]
//     public fun get_client_address_by_seed(
//         admin_addr: address,
//         client_seeds: vector<u8>
//     ): address acquires ClientStore {
//         let maps = borrow_global<ClientStore>(admin_addr);

//         if (!simple_map::contains_key(&maps.clientMap, &client_seeds)) {
//             abort E_NOT_REGISTERED;
//         };

//         *simple_map::borrow(&maps.clientMap, &client_seeds)
//     }

//     // ====== Get client balance ======
//     // public fun get_client_balance<CoinType>(admin: &signer, client_seeds: vector<u8>): u64 acquires ClientStore {
//     //     assert_admin(admin);
//     //     let client_addr = get_client_address_or_abort(admin, &client_seeds);
//     //     // coin::balance<CoinType>(client_addr)
//     // }
// }
