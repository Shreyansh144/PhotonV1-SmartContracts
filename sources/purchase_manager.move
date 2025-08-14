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

// // PurchaseManager	10000 PAT	
// // Admin		
		
// // Smart Config		
// // UserPurchased_Claimed	map<userAddress, quantity>	{"0xabc": {"fliq": 10, "fanCraze": 5}}
// // CurrentPurchaseManagerBalance	10000	
// // MaxAmountPerUser	1000	
		
		
// // isFunctionDisabled	map<string, true>	
		
// // Smart Calls		
// // claimPurchase(&signer, quanitity, metadata, clientAddress, attestation)	- verify attestation	
// // 	- client-address has balance, and user has recieved money more or equal than configure	"- amountPerUser = 10
// // - airdropClaimed[signer.address][clientAddress] >= 10: revert
// // - amountToBeClaimed = amountPerUser - airdropClaimed[signer.address][clientAddress]
// // - feesCalculation = calculateFees()

// // - airdropClientWallet[clientAddress] > amountToBeClaimed
// // - airdropClientWallet[clientAddress] - amountToBeClaimed
// // - airdropClaimed[signer.address][clientAddress] + amountToBeClaimed
// // - tokenTransfer(signer.address, amountToBeClaimed)" use this data help me build aptos smart contract on it. need to have resource account, here's the reference of aptos resource account- /// Initialize the airdrop manager with resource account
// //     public entry fun init_airdrop_manager(admin: &signer) {
// //         let admin_addr = signer::address_of(admin);
// //         assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));

// //         // Create resource account for airdrop manager
// //         let (airdrop_resource_signer, airdrop_cap) = account::create_resource_account(admin, b"airdrop_manager_test_2");
// //         let resource_addr = signer::address_of(&airdrop_resource_signer);
// //         let airdrop_signer_from_cap = account::create_signer_with_capability(&airdrop_cap);


// //         // Store capabilities in resource account
// //         move_to(&airdrop_signer_from_cap, Capabilities {
// //             admin_signer_cap: airdrop_cap,
// //         });

// //         // Initialize airdrop manager state
// //         move_to(&airdrop_signer_from_cap, AirdropManager {
// //             airdrop_amount_per_user: simple_map::create(),
// //             airdrop_claimed: simple_map::create(),
// //             airdrop_client_wallet: simple_map::create(),
// //         });

// //         move_to(admin, AdminStore { 
// //             owner: admin_addr,
// //             resource_account_address: resource_addr,
// //         });

// //         // Ensure primary store exists for the resource account
// //         primary_fungible_store::ensure_primary_store_exists(resource_addr, get_metadata());
// //     }just take as reference for purchase manager
