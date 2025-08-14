module photon_purchase_manager_deployer::PurchaseManagerModule {
    use std::signer;
    use std::error;
    use std::option;
    use std::string;
    use std::vector;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use pat_token_deployer::pat_coin::{Self, transfer, get_metadata};
    use photon_client_deployer::PhotonClientModule; 

    const E_INVALID_OWNER: u64 = 1;
    const E_AMOUNT_EXCEEDS_MAX: u64 = 2;
    const E_INSUFFICIENT_CLIENT_BALANCE: u64 = 3;
    const E_NOT_REGISTERED: u64 = 4;
    const E_OWNER_NOT_INITIALIZED: u64 = 5;
    const E_CLIENT_NOT_REGISTERED: u64 = 6;
    const E_INVALID_QUANTITY: u64 = 7;
    const E_ALREADY_CLAIMED: u64 = 8;

    const PHOTON_ADMIN: address = @photon_admin;

    /// Storage for Purchase Manager
    struct PurchaseManager has key {
        max_amount_per_user: u64,
        user_purchased_claimed: SimpleMap<address, SimpleMap<address, u64>>, // user -> client -> amount claimed
        client_wallets: SimpleMap<address, u64>, // client address -> PAT balance in manager
    }

    struct Capabilities has key {
        signer_cap: account::SignerCapability,
    }

    /// Store admin + resource account address
    struct AdminStore has key {
        owner: address,
        resource_account_address: address,
    }

    /// Helper function to validate if client is registered in PhotonClientModule
    fun assert_client_registered(client_address: address) {
        assert!(
            PhotonClientModule::is_client_registered(client_address),
            error::invalid_argument(E_CLIENT_NOT_REGISTERED)
        );
    }

    /// Init Purchase Manager with a resource account
    public entry fun initialize_purchase_manager(admin: &signer, max_per_user: u64) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));

        let (pm_signer, pm_cap) = account::create_resource_account(admin, b"purchase_manager_test_3");
        let resource_addr = signer::address_of(&pm_signer);
        let pm_signer_from_cap = account::create_signer_with_capability(&pm_cap);

        move_to(&pm_signer_from_cap, Capabilities {
            signer_cap: pm_cap,
        });
        
        move_to(&pm_signer_from_cap, PurchaseManager {
            max_amount_per_user: max_per_user,
            user_purchased_claimed: simple_map::create(),
            client_wallets: simple_map::create(),
        });

        move_to(admin, AdminStore {
            owner: admin_addr,
            resource_account_address: resource_addr,
        });

        primary_fungible_store::ensure_primary_store_exists(resource_addr, get_metadata());
    }

    /// Admin can set the max amount per user
    public entry fun set_max_amount_per_user(admin: &signer, new_limit: u64) acquires PurchaseManager, AdminStore {
        let admin_data = borrow_global<AdminStore>(signer::address_of(admin));
        assert!(signer::address_of(admin) == admin_data.owner, error::invalid_argument(E_INVALID_OWNER));

        let pm = borrow_global_mut<PurchaseManager>(admin_data.resource_account_address);
        pm.max_amount_per_user = new_limit;
    }

    /// Admin funds a client wallet in the purchase manager
    public entry fun fund_client_wallet(admin: &signer, client_addr: address, quantity: u64) acquires PurchaseManager, AdminStore {
        // Verify admin is the owner
        let admin_data = borrow_global<AdminStore>(signer::address_of(admin));
        assert!(signer::address_of(admin) == admin_data.owner, error::invalid_argument(E_INVALID_OWNER));
        
        // Validate client is registered
        assert_client_registered(client_addr);

        // Check quantity is greater than 0
        assert!(quantity > 0, error::invalid_argument(E_INVALID_QUANTITY));

        // Get PurchaseManager
        let pm = borrow_global_mut<PurchaseManager>(admin_data.resource_account_address);

        // Initialize client wallet balance if it doesn't exist
        if (!simple_map::contains_key(&pm.client_wallets, &client_addr)) {
            simple_map::add(&mut pm.client_wallets, client_addr, 0);
        };

        // Update client wallet balance
        let bal = simple_map::borrow_mut(&mut pm.client_wallets, &client_addr);
        *bal = *bal + quantity;

        // Transfer tokens to resource account
        let resource_addr = get_resource_address();
        primary_fungible_store::ensure_primary_store_exists(resource_addr, get_metadata());
        transfer(admin, resource_addr, quantity);
    }

    /// User claims purchase
    public entry fun claim_purchase(
        user: &signer,
        quantity: u64,
        client_addr: address
    ) acquires PurchaseManager, AdminStore, Capabilities {
        // Validate client is registered
        assert_client_registered(client_addr);
        let user_addr = signer::address_of(user);

        // Check quantity is greater than 0
        assert!(quantity > 0, error::invalid_argument(E_INVALID_QUANTITY));

        // Get PurchaseManager from AdminStore
        let admin_data = borrow_global<AdminStore>(PHOTON_ADMIN);
        let pm = borrow_global_mut<PurchaseManager>(admin_data.resource_account_address);

        // Check if client has sufficient balance
        assert!(
            simple_map::contains_key(&pm.client_wallets, &client_addr),
            error::invalid_state(E_INSUFFICIENT_CLIENT_BALANCE)
        );
        let client_balance = *simple_map::borrow(&pm.client_wallets, &client_addr);
        assert!(client_balance >= quantity, error::invalid_state(E_INSUFFICIENT_CLIENT_BALANCE));

        // Get how much user has already claimed for this client
        let already_claimed = if (simple_map::contains_key(&pm.user_purchased_claimed, &user_addr)) {
            let user_claims = simple_map::borrow(&pm.user_purchased_claimed, &user_addr);
            if (simple_map::contains_key(user_claims, &client_addr)) {
                *simple_map::borrow(user_claims, &client_addr)
            } else {
                0
            }
        } else {
            0
        };

        // Calculate remaining claimable amount
        let max_amount = pm.max_amount_per_user;
        let remaining_claimable = max_amount - already_claimed;

        // Check user hasn't already claimed everything
        assert!(remaining_claimable > 0, error::invalid_argument(E_ALREADY_CLAIMED));

        // Check requested quantity doesn't exceed remaining claimable amount
        assert!(
            quantity <= remaining_claimable,
            error::invalid_argument(E_AMOUNT_EXCEEDS_MAX)
        );

        // Deduct from client's balance
        let client_balance_ref = simple_map::borrow_mut(&mut pm.client_wallets, &client_addr);
        *client_balance_ref = client_balance - quantity;

        // Update user's claimed amount
        if (!simple_map::contains_key(&pm.user_purchased_claimed, &user_addr)) {
            simple_map::add(&mut pm.user_purchased_claimed, user_addr, simple_map::create<address, u64>());
        };
        let user_claims = simple_map::borrow_mut(&mut pm.user_purchased_claimed, &user_addr);
        if (simple_map::contains_key(user_claims, &client_addr)) {
            let claimed_ref = simple_map::borrow_mut(user_claims, &client_addr);
            *claimed_ref = already_claimed + quantity;
        } else {
            simple_map::add(user_claims, client_addr, quantity);
        };

        // Transfer tokens to user
        let resource_addr = get_resource_address();
        let capabilities = borrow_global<Capabilities>(resource_addr);
        let resource_signer = account::create_signer_with_capability(&capabilities.signer_cap);

        primary_fungible_store::ensure_primary_store_exists(user_addr, get_metadata());
        transfer(&resource_signer, user_addr, quantity);
    }

    /// Get resource account address
    public fun get_resource_address(): address acquires AdminStore{
        if (!exists<AdminStore>(PHOTON_ADMIN)) {
            abort E_OWNER_NOT_INITIALIZED;
        };

        let admin_store_data = borrow_global<AdminStore>(PHOTON_ADMIN);
        let resource_addr = admin_store_data.resource_account_address;
        resource_addr
    }

    /// View: Get how much a user has claimed from a client
    #[view]
    public fun get_user_claimed(user_addr: address, client_addr: address): u64 acquires PurchaseManager, AdminStore {
        let admin_data = borrow_global<AdminStore>(PHOTON_ADMIN);
        let pm = borrow_global<PurchaseManager>(admin_data.resource_account_address);
        if (simple_map::contains_key(&pm.user_purchased_claimed, &user_addr)) {
            let inner_map = simple_map::borrow(&pm.user_purchased_claimed, &user_addr);
            if (simple_map::contains_key(inner_map, &client_addr)) {
                return *simple_map::borrow(inner_map, &client_addr)
            }
        };
        0
    }

    /// View: Get client wallet balance in purchase manager
    #[view]
    public fun get_client_wallet_balance(client_addr: address): u64 acquires PurchaseManager, AdminStore {
        let admin_data = borrow_global<AdminStore>(PHOTON_ADMIN);
        let pm = borrow_global<PurchaseManager>(admin_data.resource_account_address);
        if (simple_map::contains_key(&pm.client_wallets, &client_addr)) {
            return *simple_map::borrow(&pm.client_wallets, &client_addr)
        };
        0
    }
}
