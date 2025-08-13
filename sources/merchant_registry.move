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
    struct MerchantStoreManager has key {
        merchant_signer_cap: account::SignerCapability, // Resource account signer capability
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
            let (merchant_manager, merchant_cap) = account::create_resource_account(admin, b"merchant_manager_test_2");
            let merchant_manager_addr = signer::address_of(&merchant_manager);
            let merchant_signer_from_cap = account::create_signer_with_capability(&merchant_cap);
            
            move_to(&merchant_signer_from_cap, MerchantStoreManager {
                merchant_signer_cap: merchant_cap,
            });
            move_to(admin, AdminStore { 
                owner: admin_addr,
                merchant_manager_address: merchant_manager_addr,
            });
            primary_fungible_store::ensure_primary_store_exists(admin_addr, get_metadata());
        };
    }

    // ====== Credit merchant wallet ======
    public entry fun credit_merchant_wallet(user: &signer, amount: u128) acquires AdminStore{
        let user_addr = signer::address_of(user);
      
        let merchant_addr = get_merchant_manager_address();

        if (!exists<MerchantStoreManager>(merchant_addr)) { 
            abort E_MANAGER_NOT_INITIALIZED;
        };
        
        if (amount == 0) {
            abort E_INVALID_AMOUNT;
        };

        assert!(balance(user_addr) >= (amount as u64), error::invalid_argument(E_USER_NOT_HAVING_ENOUGH_COIN));

        primary_fungible_store::ensure_primary_store_exists(merchant_addr, get_metadata());
        transfer(user, merchant_addr, (amount as u64));
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

}
