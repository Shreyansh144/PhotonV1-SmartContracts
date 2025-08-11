// module PhotonResourceAddress::spend_manager {
//     use std::signer;
//     use PhotonResourceAddress::client_registry;
//     use PhotonResourceAddress::user_registry;
//     use PhotonResourceAddress::merchant_registry;
//     use PhotonResourceAddress::admin;

//     /// Initialize (optional) - we rely on other modules' initializes; included for symmetry
//     public entry fun initialize(admin: &signer) {
//         // no resource stored for now; access enforced by admin::assert_is_admin externally
//         0xA1::admin::assert_is_admin(admin);
//     }

//     /// Make payment from user internal numeric balance to merchant manager wallet.
//     /// This consumes user's numeric balance and credits merchant manager numeric wallet.
//     public entry fun make_payment_to_merchant(reg_owner: &signer, user_addr: address, merchant_manager_owner: address, amount: u128) acquires user_registry::UserRegistry, merchant_registry::MerchantStoreManager {
//         // reg_owner must be admin/registry owner that controls user_registry
//         let owner_addr = signer::address_of(reg_owner);
//         // debit user
//         0xA1::user_registry::debit_user_balance(reg_owner, user_addr, amount);
//         // credit merchant manager numeric pool
//         // to credit manager wallet we require admin signer; borrow manager at merchant_manager_owner and update
//         let mgr_addr = merchant_manager_owner;
//         0xA1::merchant_registry::credit_manager_wallet(reg_owner, amount); // note: this API expects admin signer; reuse reg_owner
//     }

//     /// Claim tokens to user wallet from admin pool (simulate payout)
//     public entry fun claim_to_user_wallet(admin: &signer, reg_owner: address, user_addr: address, amount: u128) acquires admin::Admin, user_registry::UserRegistry {
//         let admin_addr = signer::address_of(admin);
//         // admin must be admin
//         0xA1::admin::assert_is_admin(admin);
//         // debit admin numeric pool
//         0xA1::admin::debit_admin_wallet(admin_addr, amount);
//         // credit user numeric
//         // reg_owner must be signer for user registry; here we require admin to perform the credit via create API
//         0xA1::user_registry::credit_user_balance(admin, user_addr, amount);
//     }
// }
