module purchase_manager::purchase_manager {
    use std::signer;
    use std::string::String;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_std::simple_map::{Self, SimpleMap};

    // Error codes
    const E_INVALID_OWNER: u64 = 1;
    const E_FUNCTION_DISABLED: u64 = 2;
    const E_INSUFFICIENT_BALANCE: u64 = 3;
    const E_EXCEEDS_MAX_AMOUNT: u64 = 4;
    const E_INVALID_ATTESTATION: u64 = 5;

    // Constants
    const PURCHASE_MANAGER_ADMIN: address = @0x123; // Replace with actual admin address
    const MAX_AMOUNT_PER_USER: u64 = 1000;
    const INITIAL_BALANCE: u64 = 10000;

    // Structs
    struct Capabilities has key {
        admin_signer_cap: account::SignerCapability,
    }

    struct PurchaseManager has key {
        user_purchased_claimed: SimpleMap<address, SimpleMap<String, u64>>,
        current_balance: u64,
        max_amount_per_user: u64,
        is_function_disabled: SimpleMap<String, bool>,
    }

    struct AdminStore has key {
        owner: address,
        resource_account_address: address,
    }

    // Initialize the purchase manager with resource account
    public entry fun init_purchase_manager(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == PURCHASE_MANAGER_ADMIN, E_INVALID_OWNER);

        // Create resource account for purchase manager
        let (purchase_resource_signer, purchase_cap) = account::create_resource_account(admin, b"purchase_manager");
        let resource_addr = signer::address_of(&purchase_resource_signer);
        let purchase_signer_from_cap = account::create_signer_with_capability(&purchase_cap);

        // Store capabilities in resource account
        move_to(&purchase_signer_from_cap, Capabilities {
            admin_signer_cap: purchase_cap,
        });

        // Initialize purchase manager state
        let user_purchased_claimed = simple_map::create<address, SimpleMap<String, u64>>();
        let client_map = simple_map::create<String, u64>();
        simple_map::add(&mut client_map, string::utf8(b"fliq"), 10);
        simple_map::add(&mut client_map, string::utf8(b"fanCraze"), 5);
        simple_map::add(&mut user_purchased_claimed, @0xabc, client_map);

        move_to(&purchase_signer_from_cap, PurchaseManager {
            user_purchased_claimed,
            current_balance: INITIAL_BALANCE,
            max_amount_per_user: MAX_AMOUNT_PER_USER,
            is_function_disabled: simple_map::create(),
        });

        move_to(admin, AdminStore {
            owner: admin_addr,
            resource_account_address: resource_addr,
        });

        // Ensure primary store exists for the resource account
        primary_fungible_store::ensure_primary_store_exists(resource_addr, get_metadata());
    }

    // Helper function to get metadata (replace with actual metadata object)
    fun get_metadata(): Object<Metadata> {
        object::create_named_object(PURCHASE_MANAGER_ADMIN, b"purchase_token")
    }

    // Claim purchase function
    public entry fun claim_purchase(
        signer: &signer,
        quantity: u64,
        metadata: Object<Metadata>,
        client_address: address,
        attestation: vector<u8>
    ) acquires PurchaseManager {
        let purchase_manager = borrow_global_mut<PurchaseManager>(get_resource_account_address());
        
        // Verify attestation (implement actual verification logic)
        assert!(verify_attestation(attestation), E_INVALID_ATTESTATION);

        // Check if function is disabled
        let function_name = string::utf8(b"claim_purchase");
        if (simple_map::contains_key(&purchase_manager.is_function_disabled, &function_name)) {
            assert!(!*simple_map::borrow(&purchase_manager.is_function_disabled, &function_name), E_FUNCTION_DISABLED);
        };

        let signer_addr = signer::address_of(signer);
        let amount_per_user = 10; // As specified in the smart call

        // Check if user has exceeded claim limit
        let user_claimed_map = simple_map::borrow_mut(&mut purchase_manager.user_purchased_claimed, &signer_addr);
        let claimed_amount = if (simple_map::contains_key(user_claimed_map, &string::utf8(b"fliq"))) {
            *simple_map::borrow(user_claimed_map, &string::utf8(b"fliq"))
        } else {
            0
        };

        assert!(claimed_amount >= amount_per_user, E_EXCEEDS_MAX_AMOUNT);
        let amount_to_be_claimed = amount_per_user - claimed_amount;

        // Check client wallet balance
        let client_balance = primary_fungible_store::balance(client_address, metadata);
        assert!(client_balance >= amount_to_be_claimed, E_INSUFFICIENT_BALANCE);

        // Calculate fees (implement actual fee calculation logic)
        let _fees = calculate_fees();

        // Update balances
        primary_fungible_store::decrease_balance(client_address, metadata, amount_to_be_claimed);
        if (!simple_map::contains_key(user_claimed_map, &string::utf8(b"fliq"))) {
            simple_map::add(user_claimed_map, string::utf8(b"fliq"), amount_to_be_claimed);
        } else {
            let current_amount = simple_map::borrow_mut(user_claimed_map, &string::utf8(b"fliq"));
            *current_amount = *current_amount + amount_to_be_claimed;
        };

        // Transfer tokens
        primary_fungible_store::transfer(
            &account::create_signer_with_capability(&borrow_global<Capabilities>(get_resource_account_address()).admin_signer_cap),
            metadata,
            signer_addr,
            amount_to_be_claimed
        );

        purchase_manager.current_balance = purchase_manager.current_balance - amount_to_be_claimed;
    }

    // Helper function to get resource account address
    fun get_resource_account_address(): address acquires AdminStore {
        borrow_global<AdminStore>(PURCHASE_MANAGER_ADMIN).resource_account_address
    }

    // Placeholder for attestation verification
    fun verify_attestation(_attestation: vector<u8>): bool {
        // Implement actual attestation verification logic
        true
    }

    // Placeholder for fee calculation
    fun calculate_fees(): u64 {
        // Implement actual fee calculation logic
        0
    }
}

// PurchaseManager	10000 PAT	
// Admin		
		
// Smart Config		
// UserPurchased_Claimed	map<userAddress, quantity>	{"0xabc": {"fliq": 10, "fanCraze": 5}}
// CurrentPurchaseManagerBalance	10000	
// MaxAmountPerUser	1000	
		
		
// isFunctionDisabled	map<string, true>	
		
// Smart Calls		
// claimPurchase(&signer, quanitity, metadata, clientAddress, attestation)	- verify attestation	
// 	- client-address has balance, and user has recieved money more or equal than configure	"- amountPerUser = 10
// - airdropClaimed[signer.address][clientAddress] >= 10: revert
// - amountToBeClaimed = amountPerUser - airdropClaimed[signer.address][clientAddress]
// - feesCalculation = calculateFees()

// - airdropClientWallet[clientAddress] > amountToBeClaimed
// - airdropClientWallet[clientAddress] - amountToBeClaimed
// - airdropClaimed[signer.address][clientAddress] + amountToBeClaimed
// - tokenTransfer(signer.address, amountToBeClaimed)" use this data help me build aptos smart contract on it. need to have resource account, here's the reference of aptos resource account- /// Initialize the airdrop manager with resource account
//     public entry fun init_airdrop_manager(admin: &signer) {
//         let admin_addr = signer::address_of(admin);
//         assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));

//         // Create resource account for airdrop manager
//         let (airdrop_resource_signer, airdrop_cap) = account::create_resource_account(admin, b"airdrop_manager_test_2");
//         let resource_addr = signer::address_of(&airdrop_resource_signer);
//         let airdrop_signer_from_cap = account::create_signer_with_capability(&airdrop_cap);


//         // Store capabilities in resource account
//         move_to(&airdrop_signer_from_cap, Capabilities {
//             admin_signer_cap: airdrop_cap,
//         });

//         // Initialize airdrop manager state
//         move_to(&airdrop_signer_from_cap, AirdropManager {
//             airdrop_amount_per_user: simple_map::create(),
//             airdrop_claimed: simple_map::create(),
//             airdrop_client_wallet: simple_map::create(),
//         });

//         move_to(admin, AdminStore { 
//             owner: admin_addr,
//             resource_account_address: resource_addr,
//         });

//         // Ensure primary store exists for the resource account
//         primary_fungible_store::ensure_primary_store_exists(resource_addr, get_metadata());
//     }just take as reference for purchase manager
