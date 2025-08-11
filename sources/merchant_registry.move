// module PhotonResourceAddress::merchant_registry {
//     use std::signer;
//     use std::timestamp;
//     use PhotonResourceAddress::common_utils;

//     resource struct MerchantStoreManager {
//         merchant_accounts: vector::Vector<(address, bool)>, // merchant_address -> active flag
//         wallet_balance: u128, // numeric pool that holds PAT for merchant operations (single manager)
//         coin_type_address: address, // keep the coin type address or symbol reference (placeholder)
//         created_at: u64,
//         merchant_signer_cap: account::SignerCapability, // Resource account signer capability

//     }

//     public entry fun initialize(admin: &signer, coin_type_address: address) {
//         let addr = signer::address_of(admin);
//         assert!(!exists<MerchantStoreManager>(addr), 0);
//         move_to(admin, MerchantStoreManager {
//             owner: addr,
//             merchant_accounts: vector::empty(),
//             wallet_balance: 0u128,
//             coin_type_address,
//             created_at: timestamp::now_seconds(),
//         });
//     }

//     public entry fun register_merchant(admin: &signer, merchant_addr: address) acquires MerchantStoreManager {
//         let owner_addr = signer::address_of(admin);
//         assert!(exists<MerchantStoreManager>(owner_addr), 1);
//         let mgr = borrow_global_mut<MerchantStoreManager>(owner_addr);
//         // ensure not already present
//         let idx_opt = common_utils::index_of_addr(&mgr.merchant_accounts, merchant_addr);
//         assert!(option::is_none(&idx_opt), 2);
//         vector::push_back(&mut mgr.merchant_accounts, (merchant_addr, true));
//     }

//     public entry fun update_merchant_status(admin: &signer, merchant_addr: address, active: bool) acquires MerchantStoreManager {
//         let owner_addr = signer::address_of(admin);
//         assert!(exists<MerchantStoreManager>(owner_addr), 3);
//         let mgr = borrow_global_mut<MerchantStoreManager>(owner_addr);
//         let idx_opt = common_utils::index_of_addr(&mgr.merchant_accounts, merchant_addr);
//         assert!(option::is_some(&idx_opt), 4);
//         let idx = option::extract(idx_opt);
//         let (_, flag) = *common_utils::borrow_by_index(&mgr.merchant_accounts, idx);
//         common_utils::remove_by_index(&mut mgr.merchant_accounts, idx);
//         vector::push_back(&mut mgr.merchant_accounts, (merchant_addr, active));
//     }

//     /// Credit manager wallet (increase numeric merchant pool)
//     public entry fun credit_manager_wallet(admin: &signer, amount: u128) acquires MerchantStoreManager {
//         let owner_addr = signer::address_of(admin);
//         assert!(exists<MerchantStoreManager>(owner_addr), 5);
//         let mgr = borrow_global_mut<MerchantStoreManager>(owner_addr);
//         mgr.wallet_balance = mgr.wallet_balance + amount;
//     }

//     /// Redeem from merchant: move merchant's numeric 'share' to admin wallet (we model merchant share by decreasing manager wallet)
//     /// Caller must be admin for now (could be merchant later with access check)
//     public entry fun redeem_from_merchant(admin: &signer, amount: u128, admin_addr_for_credit: address) acquires MerchantStoreManager {
//         let owner_addr = signer::address_of(admin);
//         assert!(exists<MerchantStoreManager>(owner_addr), 6);
//         let mgr = borrow_global_mut<MerchantStoreManager>(owner_addr);
//         assert!(mgr.wallet_balance >= amount, 7);
//         mgr.wallet_balance = mgr.wallet_balance - amount;
//         // Credit admin's wallet numeric via admin module (callable by Move cross-module later)
//         0xA1::admin::credit_admin_wallet(admin_addr_for_credit, amount);
//     }

//     public fun get_manager_balance(owner_addr: address): u128 acquires MerchantStoreManager {
//         assert!(exists<MerchantStoreManager>(owner_addr), 8);
//         borrow_global<MerchantStoreManager>(owner_addr).wallet_balance
//     }
// }
