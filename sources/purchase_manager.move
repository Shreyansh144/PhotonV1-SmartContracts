// module photon_purchase_manager::PhotonPurchaseManagerModule {
//     use std::signer;
//     use photon_user_module_deployer::PhotonUsersModule::{ Self, credit_tokens};
//     use photon_admin_deployer::PhotonAdmin::{Self, debit_admin_manager_wallet};
//     use pat_token_deployer::pat_coin::{ Self, get_metadata};
//     use aptos_framework::primary_fungible_store;

//     const E_INVALID_AMOUNT: u64 = 1;

//     public entry fun purchase_from_admin_manager(
//         user: &signer,
//         amount: u128,
//     ) {
//         assert!(amount > 0, E_INVALID_AMOUNT);

//         let user_addr = signer::address_of(user);
//         primary_fungible_store::ensure_primary_store_exists(user_addr, get_metadata());

//         debit_admin_manager_wallet(user,amount);
//         credit_tokens(user,amount);
//     }
// }
