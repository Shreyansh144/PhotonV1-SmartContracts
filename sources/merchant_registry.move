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
    use aptos_std::table::{Self, Table}; 

    const E_NOT_ADMIN: u64 = 1;
    const E_OWNER_NOT_INITIALIZED: u64 = 2;
    const E_USER_NOT_HAVING_ENOUGH_COIN: u64 = 3;
    const E_MERCHANT_NOT_HAVING_ENOUGH_COIN: u64 = 4;
    const E_MANAGER_NOT_INITIALIZED: u64 = 5;
    const E_INVALID_AMOUNT: u64 = 6;
    const E_INVALID_OWNER: u64 = 7;
    const E_ALREADY_EXISTS: u64 = 8;
    const E_INVALID_MERCHANT_ID: u64 = 9;

    const PHOTON_ADMIN: address = @photon_admin;

    struct AdminStore has key {
        owner: address,
        merchant_manager_address: address
    }

    struct MerchantStoreManager has key, store {
        merchant_signer_cap: account::SignerCapability, 
        merchantMap: Table<u64, Merchant>,
        merchant_counter: u64,                
    }

    struct Merchant has store, drop, copy {
        name: String,
        description: String,
        tags: vector<String>,
        quantity: u128  // Fixed typo: was "quanitity"
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
            let (merchant_manager, merchant_cap) = account::create_resource_account(admin, b"merchant_manager_test_4");
            let merchant_manager_addr = signer::address_of(&merchant_manager);
            let merchant_signer_from_cap = account::create_signer_with_capability(&merchant_cap);
            
            move_to(&merchant_signer_from_cap, MerchantStoreManager {
                merchant_signer_cap: merchant_cap,
                merchantMap: table::new(),
                merchant_counter: 0
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

        let manager = borrow_global_mut<MerchantStoreManager>(merchant_addr);

        // Fixed: Use table instead of simple_map
        if (table::contains(&manager.merchantMap, merchant_id)) {
            let merchant_ref = table::borrow_mut(&mut manager.merchantMap, merchant_id);
            merchant_ref.quantity = merchant_ref.quantity + amount;
        } else {
            abort(E_INVALID_MERCHANT_ID);
        };

        primary_fungible_store::ensure_primary_store_exists(merchant_addr, get_metadata());
        transfer(user, merchant_addr, (amount as u64));
    }

    public entry fun settlement_by_admin(
        admin: &signer, 
        merchant_id: u64,
        amount: u128
    ) acquires AdminStore, MerchantStoreManager {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let merchant_addr = get_merchant_manager_address();

        if (!exists<MerchantStoreManager>(merchant_addr)) { 
            abort E_MANAGER_NOT_INITIALIZED;
        };

        if (amount == 0) {
            abort E_INVALID_AMOUNT;
        };

        let manager = borrow_global_mut<MerchantStoreManager>(merchant_addr);
        
        // Check if merchant exists and has enough balance
        if (!table::contains(&manager.merchantMap, merchant_id)) {
            abort(E_INVALID_MERCHANT_ID);
        };

        let merchant_ref = table::borrow_mut(&mut manager.merchantMap, merchant_id);
        if (merchant_ref.quantity < amount) {
            abort(E_MERCHANT_NOT_HAVING_ENOUGH_COIN);
        };

        // Deduct from merchant balance
        merchant_ref.quantity = merchant_ref.quantity - amount;

        assert!(balance(merchant_addr) >= (amount as u64), error::invalid_argument(E_MERCHANT_NOT_HAVING_ENOUGH_COIN));

        let merchant_signer_from_cap = account::create_signer_with_capability(&manager.merchant_signer_cap);

        primary_fungible_store::ensure_primary_store_exists(admin_addr, get_metadata());
        transfer(&merchant_signer_from_cap, admin_addr, (amount as u64));
    }

     public entry fun settlement_multiple_merchants_wallet(
        admin: &signer,
        merchant_ids: vector<u64>,
        amounts: vector<u128>
    ) acquires AdminStore, MerchantStoreManager {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let merchant_addr = get_merchant_manager_address();

        if (!exists<MerchantStoreManager>(merchant_addr)) { 
            abort E_MANAGER_NOT_INITIALIZED;
        };

        let merchant_count = vector::length(&merchant_ids);
        let amount_count = vector::length(&amounts);
        assert!(merchant_count == amount_count, error::invalid_argument(E_INVALID_AMOUNT));
        assert!(merchant_count > 0, error::invalid_argument(E_INVALID_AMOUNT));

        let manager = borrow_global_mut<MerchantStoreManager>(merchant_addr);
        let total_amount: u128 = 0;
        let i = 0;

        while (i < merchant_count) {
            let merchant_id = *vector::borrow(&merchant_ids, i);
            let amount = *vector::borrow(&amounts, i);

            if (amount == 0) {
                abort E_INVALID_AMOUNT;
            };

            if (!table::contains(&manager.merchantMap, merchant_id)) {
                abort E_INVALID_MERCHANT_ID;
            };

            let merchant_ref = table::borrow(&manager.merchantMap, merchant_id);
            if (merchant_ref.quantity < amount) {
                abort E_MERCHANT_NOT_HAVING_ENOUGH_COIN;
            };

            total_amount = total_amount + amount;
            i = i + 1;
        };

        assert!(
            balance(merchant_addr) >= (total_amount as u64), 
            error::invalid_argument(E_MERCHANT_NOT_HAVING_ENOUGH_COIN)
        );

        i = 0;
        while (i < merchant_count) {
            let merchant_id = *vector::borrow(&merchant_ids, i);
            let amount = *vector::borrow(&amounts, i);

            let merchant_ref = table::borrow_mut(&mut manager.merchantMap, merchant_id);
            merchant_ref.quantity = merchant_ref.quantity - amount;

            i = i + 1;
        };

        // Transfer total amount to admin
        let merchant_signer_from_cap = account::create_signer_with_capability(&manager.merchant_signer_cap);
        primary_fungible_store::ensure_primary_store_exists(admin_addr, get_metadata());
        transfer(&merchant_signer_from_cap, admin_addr, (total_amount as u64));
    }

    public fun get_merchant_manager_address(): address acquires AdminStore {
        if (!exists<AdminStore>(PHOTON_ADMIN)) {
            abort E_OWNER_NOT_INITIALIZED;
        };

        let admin_store_data = borrow_global<AdminStore>(PHOTON_ADMIN);
        let merchant_addr = admin_store_data.merchant_manager_address;
        merchant_addr
    }

    public entry fun create_merchant_id(
        admin: &signer,
        name: String,
        description: String,
        tags: vector<String>
    ) acquires MerchantStoreManager, AdminStore {
        assert_admin(admin);
        let merchant_addr = get_merchant_manager_address();

        if (!exists<MerchantStoreManager>(merchant_addr)) {
            abort E_MANAGER_NOT_INITIALIZED;
        };

        let manager = borrow_global_mut<MerchantStoreManager>(merchant_addr);
        let counter = manager.merchant_counter + 1;

        // Check if merchant already exists (optional safety check)
        if (table::contains(&manager.merchantMap, counter)) {
            abort E_ALREADY_EXISTS;
        };

        let new_merchant = Merchant {
            name,
            description,
            tags,
            quantity: 0
        };

        table::add(&mut manager.merchantMap, counter, new_merchant);
        manager.merchant_counter = counter;
    }

    #[view]
    public fun get_merchant_balance(
        merchant_id: u64
    ): u128 acquires MerchantStoreManager, AdminStore {
        let merchant_addr = get_merchant_manager_address();
        let manager = borrow_global<MerchantStoreManager>(merchant_addr);

        if (table::contains(&manager.merchantMap, merchant_id)) {
            let merchant = table::borrow(&manager.merchantMap, merchant_id);
            merchant.quantity
        } else {
            0
        }
    }

    #[view]
    public fun get_merchant_info(
        merchant_id: u64
    ): (String, String, vector<String>, u128) acquires MerchantStoreManager, AdminStore {
        let merchant_addr = get_merchant_manager_address();
        let manager = borrow_global<MerchantStoreManager>(merchant_addr);

        if (table::contains(&manager.merchantMap, merchant_id)) {
            let merchant = table::borrow(&manager.merchantMap, merchant_id);
            (merchant.name, merchant.description, merchant.tags, merchant.quantity)
        } else {
            abort E_INVALID_MERCHANT_ID
        }
    }

    #[view]
    public fun get_merchant_counter(): u64 acquires MerchantStoreManager, AdminStore {
        let merchant_addr = get_merchant_manager_address();
        let manager = borrow_global<MerchantStoreManager>(merchant_addr);
        manager.merchant_counter
    }
}