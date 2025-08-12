module photon_merchant_deployer::PhotonMerchantManagerModule {
    use std::signer;
    use std::timestamp;
    use std::vector;
    use std::error;
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use pat_token_deployer::pat_coin::{ Self, get_metadata,transfer,balance};



    // ====== ERROR CODES ======
    const E_NOT_ADMIN: u64 = 1;
    const E_NOT_REGISTERED: u64 = 2;
    const E_OWNER_NOT_HAVING_ENOUGH_COIN: u64 = 3;
    const E_ALREADY_EXISTS: u64 = 4;
    const E_MANAGER_NOT_INITIALIZED: u64 = 5;
    const E_INVALID_AMOUNT: u64 = 6;
    const E_INVALID_OWNER: u64 = 7;

    const PHOTON_ADMIN: address = @photon_admin;

    // ====== Admin resource ======
    struct Admin has key {
        owner: address,
    }

    // ====== Merchant resource stored at admin address ======
    struct MerchantStoreManager has key, store {
        merchant_total_wallet_balance: u128, // numeric pool that holds PAT for merchant operations
        merchant_signer_cap: account::SignerCapability, // Resource account signer capability
        merchant_address: address
    }

    // ====== Helpers ======
    fun assert_admin(caller: &signer) acquires Admin {
        let owner_addr = signer::address_of(caller);
        let admin_ref = borrow_global<Admin>(owner_addr);
        if (admin_ref.owner != owner_addr) {
            abort E_NOT_ADMIN;
        }
    }

    public entry fun initialize_merchant_manager(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));
        
        if (!exists<MerchantStoreManager>(admin_addr)) {
            // Create resource account for merchant management
            let (merchant_account, merchant_cap) = account::create_resource_account(admin, b"merchant_manager");
            let merchant_account_addr = signer::address_of(&merchant_account);

            
            move_to(admin, MerchantStoreManager {
                merchant_total_wallet_balance: 0,
                merchant_signer_cap: merchant_cap,
                merchant_address: merchant_account_addr
            });
            move_to(admin, Admin { owner: admin_addr });
            let metadata = get_metadata();
            primary_fungible_store::ensure_primary_store_exists(admin_addr, metadata);
        };
    }

    // ====== Credit merchant wallet ======
    public entry fun credit_merchant_wallet(user: &signer, merchant_manager_address: address, amount: u128) 
        acquires  MerchantStoreManager {
        let user_addr = signer::address_of(user);
        
        if (!exists<MerchantStoreManager>(PHOTON_ADMIN)) {
            abort E_MANAGER_NOT_INITIALIZED;
        };
        
        if (amount == 0) {
            abort E_INVALID_AMOUNT;
        };

        assert!(balance(user_addr) >= (amount as u64), error::invalid_argument(E_OWNER_NOT_HAVING_ENOUGH_COIN));
        let manager_data = borrow_global_mut<MerchantStoreManager>(PHOTON_ADMIN);
        let merchant_manager_address = manager_data.merchant_address;
        
        // Update total manager balance
        manager_data.merchant_total_wallet_balance = manager_data.merchant_total_wallet_balance + amount;
        transfer(user, merchant_manager_address, (amount as u64));
    }

    // ====== Withdraw all merchant balances (settlement) ======
    public entry fun withdraw_all_merchant_balance(admin: &signer, amount: u128) acquires Admin, MerchantStoreManager {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);

        if (!exists<MerchantStoreManager>(admin_addr)) {
            abort E_MANAGER_NOT_INITIALIZED;
        };

         if (amount == 0) {
            abort E_INVALID_AMOUNT;
        };

        let manager_data = borrow_global_mut<MerchantStoreManager>(admin_addr);
        let merchant_manager_address = manager_data.merchant_address;
        assert!(balance(merchant_manager_address) >= (amount as u64), error::invalid_argument(E_OWNER_NOT_HAVING_ENOUGH_COIN));
        
        let manager_signer_from_cap = account::create_signer_with_capability(&manager_data.merchant_signer_cap);
        manager_data.merchant_total_wallet_balance = manager_data.merchant_total_wallet_balance - amount;

        transfer(&manager_signer_from_cap, admin_addr, (amount as u64));
    }

    // ====== Get total manager balance ======
    public fun get_total_manager_balance(admin: &signer): u128 acquires Admin, MerchantStoreManager {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        
        if (!exists<MerchantStoreManager>(admin_addr)) {
            abort E_MANAGER_NOT_INITIALIZED;
        };
        
        let manager = borrow_global<MerchantStoreManager>(admin_addr);
        manager.merchant_total_wallet_balance
    }
}
