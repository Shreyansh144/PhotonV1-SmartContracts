module photon_merchant_deployer::PhotonMerchantManagerModule {
    use std::signer;
    use std::timestamp;
    use std::vector;
    use std::error;
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use pat_token_deployer::pat_coin::{ Self, get_metadata,transfer,balance};
    use aptos_std::simple_map::{Self, SimpleMap};
    use std::string::{String, utf8};


    // ====== ERROR CODES ======
    const E_NOT_ADMIN: u64 = 1;
    const E_OWNER_NOT_INITIALIZED: u64 = 2;
    const E_USER_NOT_HAVING_ENOUGH_COIN: u64 = 3;
    const E_MERCHANT_NOT_HAVING_ENOUGH_COIN: u64 = 4;
    const E_MANAGER_NOT_INITIALIZED: u64 = 5;
    const E_INVALID_AMOUNT: u64 = 6;
    const E_INVALID_OWNER: u64 = 7;
    const E_ALREADY_EXISTS: u64 = 8;

    const PHOTON_ADMIN: address = @photon_admin;

    // ====== Admin resource ======
    struct AdminStore has key {
        owner: address,
        merchant_manager_address: address
    }

    // ====== Merchant resource stored at admin address ======
    struct MerchantStoreManager has key, store {
        merchant_signer_cap: account::SignerCapability, // Resource account signer capability
        merchantMap: SimpleMap<u64, u128>,
        last_merchant_id: u64,                          // Tracks the last assigned merchant ID

    }

    // ====== Helpers ======
    fun assert_admin(caller: &signer) acquires AdminStore {
        let owner_addr = signer::address_of(caller);
        let admin_ref = borrow_global<AdminStore>(owner_addr);
        if (admin_ref.owner != owner_addr) {
            abort E_NOT_ADMIN;
        }
    }

    public entry fun initialize_merchant_manager(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));

        if (!exists<AdminStore>(admin_addr)) {
            // Create resource account for merchant management
            let (merchant_manager, merchant_cap) = account::create_resource_account(admin, b"merchant_manager_test_3");
            let merchant_manager_addr = signer::address_of(&merchant_manager);
            let merchant_signer_from_cap = account::create_signer_with_capability(&merchant_cap);
            
            move_to(&merchant_signer_from_cap, MerchantStoreManager {
                merchant_signer_cap: merchant_cap,
                merchantMap: simple_map::create(),
                last_merchant_id: 0
            });
            move_to(admin, AdminStore { 
                owner: admin_addr,
                merchant_manager_address: merchant_manager_addr,
            });
            primary_fungible_store::ensure_primary_store_exists(admin_addr, get_metadata());
        };
    }

    public entry fun credit_merchant_wallet(
        user: &signer, 
        merchant_id: u64, 
        amount: u128
    ) acquires AdminStore, MerchantStoreManager {
        let user_addr = signer::address_of(user);
        let merchant_addr = get_merchant_manager_address();

        // Ensure merchant manager exists
        if (!exists<MerchantStoreManager>(merchant_addr)) { 
            abort E_MANAGER_NOT_INITIALIZED;
        };

        if (amount == 0) {
            abort E_INVALID_AMOUNT;
        };

        assert!(
            balance(user_addr) >= (amount as u64), 
            error::invalid_argument(E_USER_NOT_HAVING_ENOUGH_COIN)
        );

        // Credit merchant's primary store
        primary_fungible_store::ensure_primary_store_exists(merchant_addr, get_metadata());
        transfer(user, merchant_addr, (amount as u64));

        // Update the merchant map
        let manager = borrow_global_mut<MerchantStoreManager>(merchant_addr);

        if (simple_map::contains_key(&manager.merchantMap, &merchant_id)) {
            // Merchant exists, increase balance
            let current_balance_ref = simple_map::borrow_mut(&mut manager.merchantMap, &merchant_id);
            *current_balance_ref = *current_balance_ref + amount;
        } else {
            // Merchant does not exist → create entry with initial balance
            // This could also call create_merchant_id if you want dynamic ID generation
            let old_id = manager.last_merchant_id;
            let new_id = old_id + 1;
            simple_map::add(&mut manager.merchantMap, new_id, amount);
            
            // Update last_merchant_id if the given ID is greater
            if (new_id > manager.last_merchant_id) {
                manager.last_merchant_id = new_id;
            }
        };
    }


    // ====== Withdraw all merchant balances (settlement) ======
    public entry fun debit_merchant_wallet(admin: &signer, amount: u128) acquires AdminStore, MerchantStoreManager {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let merchant_addr = get_merchant_manager_address();

        if (!exists<MerchantStoreManager>(merchant_addr)) { 
            abort E_MANAGER_NOT_INITIALIZED;
        };

        if (amount == 0) {
            abort E_INVALID_AMOUNT;
        };

        assert!(balance(merchant_addr) >= (amount as u64), error::invalid_argument(E_MERCHANT_NOT_HAVING_ENOUGH_COIN));

        let merchant_data = borrow_global_mut<MerchantStoreManager>(merchant_addr);
        let merchant_signer_from_cap = account::create_signer_with_capability(&merchant_data.merchant_signer_cap);

        transfer(&merchant_signer_from_cap, admin_addr, (amount as u64));
    }

    /// Function to get merchant_manager_address from AdminStore
    public fun get_merchant_manager_address(): address acquires AdminStore{
        if (!exists<AdminStore>(PHOTON_ADMIN)) {
            abort E_OWNER_NOT_INITIALIZED;
        };

        let admin_store_data = borrow_global<AdminStore>(PHOTON_ADMIN);
        let merchant_addr = admin_store_data.merchant_manager_address;
        merchant_addr
    }

    // Function to create a new merchant ID
    public entry fun create_merchant_id(
        admin: &signer
    ) acquires MerchantStoreManager, AdminStore {
        assert_admin(admin);
        let merchant_addr = get_merchant_manager_address();

        if (!exists<MerchantStoreManager>(merchant_addr)) {
            abort E_MANAGER_NOT_INITIALIZED;
        };

        let manager = borrow_global_mut<MerchantStoreManager>(merchant_addr);

        manager.last_merchant_id = manager.last_merchant_id + 1;
        let new_id = manager.last_merchant_id;

        // Ensure the merchant is initialized in the map with 0 balance
        simple_map::add(&mut manager.merchantMap, new_id, 0);
    }

    // Helper function to fetch merchant balance
    #[view]
    public fun get_merchant_balance(
        merchant_id: u64
    ): u128 acquires MerchantStoreManager,AdminStore {
        let merchant_addr = get_merchant_manager_address();
        let manager = borrow_global<MerchantStoreManager>(merchant_addr);

        if (simple_map::contains_key(&manager.merchantMap, &merchant_id)) {
            *simple_map::borrow(&manager.merchantMap, &merchant_id)
        } else {
            0
        }
    }

    // // Optional: Get all merchants (incremental fetch if you add pagination logic)
    // public fun get_all_merchants(): vector<u64, u128> acquires MerchantStoreManager {
    //     let merchant_addr = get_merchant_manager_address();
    //     let manager = borrow_global<MerchantStoreManager>(merchant_addr);
    //     simple_map::to_vec(&manager.merchantMap)
    // }

}
