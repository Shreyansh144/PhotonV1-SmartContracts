module photon_airdrop_manager_deployer::AirdropManagerModule {
    use std::signer;
    use std::error;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::object;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_std::string::{Self, String};
    use pat_token_deployer::pat_coin::{ Self, get_metadata,transfer,balance};
    use aptos_std::table::{Self, Table}; 
    use photon_client_deployer::PhotonClientModule; 

    // Error codes
    const E_INVALID_OWNER: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_ALREADY_CLAIMED: u64 = 3;
    const E_CLIENT_NOT_CONFIGURED: u64 = 4;
    const E_INVALID_ATTESTATION: u64 = 5;
    const E_NOT_AUTHORIZED: u64 = 6;
    const E_OWNER_NOT_INITIALIZED: u64 = 7;
    const E_CLIENT_NOT_REGISTERED: u64 = 7;

    const PHOTON_ADMIN: address = @photon_admin;

    struct AdminStore has key {
        owner: address,
        resource_account_address: address
    }

    struct Capabilities has key {
        admin_signer_cap: account::SignerCapability,
    }

    // Updated struct to use consistent data structures
    struct AirdropManager has key {
        // Configuration: client address -> amount per user
        airdrop_amount_per_user: SimpleMap<address, u64>,
        // Track claims: user address -> (client address -> claimed amount)
        airdrop_claimed: SimpleMap<address, SimpleMap<address, u64>>,
        // Client wallet balances: client address -> available balance
        airdrop_client_wallet: SimpleMap<address, u64>,
    }

    // ====== Helpers ======
    fun assert_admin(caller: &signer) acquires AdminStore {
        let owner_addr = signer::address_of(caller);
        let admin_ref = borrow_global<AdminStore>(owner_addr);
        if (admin_ref.owner != owner_addr) {
            abort E_INVALID_OWNER;
        }
    }

    /// Helper function to validate if client is registered in PhotonClientModule
    fun assert_client_registered(client_address: address) {
        assert!(
            PhotonClientModule::is_client_registered(client_address),
            error::invalid_argument(E_CLIENT_NOT_REGISTERED)
        );
    }

    public entry fun init_airdrop_manager(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));

        let (airdrop_resource_signer, airdrop_cap) = account::create_resource_account(admin, b"airdrop_manager_test_8");
        let resource_addr = signer::address_of(&airdrop_resource_signer);
        let airdrop_signer_from_cap = account::create_signer_with_capability(&airdrop_cap);

        move_to(&airdrop_signer_from_cap, Capabilities {
            admin_signer_cap: airdrop_cap,
        });

        move_to(&airdrop_signer_from_cap, AirdropManager {
            airdrop_amount_per_user: simple_map::create(),
            airdrop_claimed: simple_map::create(),
            airdrop_client_wallet: simple_map::create(),
        });

        move_to(admin, AdminStore { 
            owner: admin_addr,
            resource_account_address: resource_addr,
        });

        primary_fungible_store::ensure_primary_store_exists(resource_addr, get_metadata());
    }

    /// Update airdrop amount configuration for a client (called by client themselves)
    public entry fun set_airdrop_amount_per_user(
        client: &signer,
        amount_per_user: u64
    ) acquires AirdropManager, AdminStore {
        let client_address = signer::address_of(client);
        // Validate client is registered in PhotonClientModule
        assert_client_registered(client_address);

        let airdrop_manager = borrow_global_mut<AirdropManager>(get_resource_address());
                
        if (simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
            let amount_ref = simple_map::borrow_mut(&mut airdrop_manager.airdrop_amount_per_user, &client_address);
            *amount_ref = amount_per_user;
        } else {
            simple_map::add(&mut airdrop_manager.airdrop_amount_per_user, client_address, amount_per_user);
        };
    }

    /// Admin function to update airdrop amount for any client
    public entry fun set_airdrop_amount_per_user_for_admin(
        admin: &signer,
        client_address: address,
        amount_per_user: u64
    ) acquires AirdropManager, AdminStore {
        assert_admin(admin);
        let airdrop_manager = borrow_global_mut<AirdropManager>(get_resource_address());

        // Validate client is registered in PhotonClientModule
        assert_client_registered(client_address);
                
        if (simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
            let amount_ref = simple_map::borrow_mut(&mut airdrop_manager.airdrop_amount_per_user, &client_address);
            *amount_ref = amount_per_user;
        } else {
            simple_map::add(&mut airdrop_manager.airdrop_amount_per_user, client_address, amount_per_user);
        };
    }

    /// Batch update airdrop amounts for multiple clients (admin only)
    public entry fun batch_set_airdrop_amount_per_user(
        admin: &signer,
        client_addresses: vector<address>,
        amounts_per_user: vector<u64>
    ) acquires AirdropManager, AdminStore {
        assert_admin(admin);
        assert!(
            vector::length(&client_addresses) == vector::length(&amounts_per_user),
            error::invalid_argument(E_INVALID_OWNER)
        );

        let airdrop_manager = borrow_global_mut<AirdropManager>(get_resource_address());
        let len = vector::length(&client_addresses);
        let i = 0;

        while (i < len) {
            let client_address = *vector::borrow(&client_addresses, i);
            let amount_per_user = *vector::borrow(&amounts_per_user, i);

            // Validate client is registered in PhotonClientModule
            assert_client_registered(client_address);
            
            if (simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
                let amount_ref = simple_map::borrow_mut(&mut airdrop_manager.airdrop_amount_per_user, &client_address);
                *amount_ref = amount_per_user;
            } else {
                simple_map::add(&mut airdrop_manager.airdrop_amount_per_user, client_address, amount_per_user);
            };
            
            i = i + 1;
        };
    }

    public entry fun fund_client_airdrop_wallet(
        admin: &signer,
        client_address: address,
        quantity: u64
    ) acquires AirdropManager, Capabilities, AdminStore {
        let admin_addr = signer::address_of(admin);
        let resource_addr = get_resource_address();
        let admin_data = borrow_global_mut<AdminStore>(PHOTON_ADMIN);
        
        assert!(admin_addr == admin_data.owner, error::permission_denied(E_NOT_AUTHORIZED));
        
        // Validate client is registered in PhotonClientModule
        assert_client_registered(client_address);
        
        let airdrop_manager = borrow_global_mut<AirdropManager>(resource_addr);

        let current_balance = if (simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address)) {
            *simple_map::borrow(&airdrop_manager.airdrop_client_wallet, &client_address)
        } else {
            0
        };

        let new_balance = current_balance + quantity;

        if (simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address)) {
            let balance_ref = simple_map::borrow_mut(&mut airdrop_manager.airdrop_client_wallet, &client_address);
            *balance_ref = new_balance;
        } else {
            simple_map::add(&mut airdrop_manager.airdrop_client_wallet, client_address, new_balance);
        };

        primary_fungible_store::ensure_primary_store_exists(resource_addr, get_metadata());
        transfer(admin, resource_addr, quantity);
    }

    /// Claim airdrop tokens - allows partial claims up to the total allocated amount
    public entry fun claim_airdrop_tokens(
        user: &signer,
        client_address: address,
        requested_amount: u64
    ) acquires AirdropManager, Capabilities, AdminStore {
        let user_addr = signer::address_of(user);
        let resource_addr = get_resource_address();
        
        // Validate client is registered in PhotonClientModule
        assert_client_registered(client_address);
        
        let airdrop_manager = borrow_global_mut<AirdropManager>(resource_addr);

        // Check if client has configured airdrop
        assert!(
            simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address),
            error::invalid_argument(E_CLIENT_NOT_CONFIGURED)
        );

        // Get the total amount allocated per user for this client
        let amount_per_user = *simple_map::borrow(&airdrop_manager.airdrop_amount_per_user, &client_address);

        // Check user must request more than 0
        assert!(requested_amount > 0, error::invalid_argument(E_INVALID_OWNER));

        // Get how much user has already claimed from this client
        let already_claimed_amount = if (simple_map::contains_key(&airdrop_manager.airdrop_claimed, &user_addr)) {
            let user_claims = simple_map::borrow(&airdrop_manager.airdrop_claimed, &user_addr);
            if (simple_map::contains_key(user_claims, &client_address)) {
                *simple_map::borrow(user_claims, &client_address)
            } else {
                0
            }
        } else {
            0
        };

        // Calculate remaining claimable amount
        let remaining_claimable = amount_per_user - already_claimed_amount;

        // Check user hasn't already claimed everything
        assert!(remaining_claimable > 0, error::invalid_argument(E_ALREADY_CLAIMED));

        // Check requested amount doesn't exceed remaining claimable amount
        assert!(
            requested_amount <= remaining_claimable, 
            error::invalid_argument(E_ALREADY_CLAIMED)
        );

        // Check client has sufficient balance in their wallet
        assert!(
            simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address),
            error::invalid_state(E_INSUFFICIENT_BALANCE)
        );

        let client_balance = *simple_map::borrow(&airdrop_manager.airdrop_client_wallet, &client_address);
        assert!(client_balance >= requested_amount, error::invalid_state(E_INSUFFICIENT_BALANCE));

        // Deduct from client's balance
        let client_balance_ref = simple_map::borrow_mut(&mut airdrop_manager.airdrop_client_wallet, &client_address);
        *client_balance_ref = client_balance - requested_amount;

        // Update user's claimed amount
        if (!simple_map::contains_key(&airdrop_manager.airdrop_claimed, &user_addr)) {
            simple_map::add(&mut airdrop_manager.airdrop_claimed, user_addr, simple_map::create<address, u64>());
        };

        let user_claims = simple_map::borrow_mut(&mut airdrop_manager.airdrop_claimed, &user_addr);
        if (simple_map::contains_key(user_claims, &client_address)) {
            let claimed_ref = simple_map::borrow_mut(user_claims, &client_address);
            *claimed_ref = already_claimed_amount + requested_amount;
        } else {
            simple_map::add(user_claims, client_address, requested_amount);
        };

        // Transfer tokens to user
        let capabilities = borrow_global<Capabilities>(resource_addr);
        let resource_signer = account::create_signer_with_capability(&capabilities.admin_signer_cap);

        primary_fungible_store::ensure_primary_store_exists(user_addr, get_metadata());
        transfer(&resource_signer, user_addr, requested_amount);
    }

    /// Convenience function to claim all remaining tokens at once
    public entry fun claim_all_remaining_tokens(
        user: &signer,
        client_address: address,
    ) acquires AirdropManager, Capabilities, AdminStore {
        // Validate client is registered in PhotonClientModule
        assert_client_registered(client_address);

        let user_addr = signer::address_of(user);
        let remaining = get_remaining_claimable(user_addr, client_address);
        
        assert!(remaining > 0, error::invalid_argument(E_ALREADY_CLAIMED));
        
        claim_airdrop(user, client_address, remaining);
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

    /// View functions for querying state
    #[view]
    public fun get_client_airdrop_amount(client_address: address): u64 acquires AirdropManager,AdminStore {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        if (simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
            *simple_map::borrow(&airdrop_manager.airdrop_amount_per_user, &client_address)
        } else {
            0
        }
    }

    #[view]
    public fun get_airdrop_client_balance(client_address: address): u64 acquires AirdropManager ,AdminStore{
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        if (simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address)) {
            *simple_map::borrow(&airdrop_manager.airdrop_client_wallet, &client_address)
        } else {
            0
        }
    }

    #[view]
    public fun get_user_claimed_amount(user_address: address, client_address: address): u64 acquires AirdropManager,AdminStore {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        if (simple_map::contains_key(&airdrop_manager.airdrop_claimed, &user_address)) {
            let user_claims = simple_map::borrow(&airdrop_manager.airdrop_claimed, &user_address);
            if (simple_map::contains_key(user_claims, &client_address)) {
                *simple_map::borrow(user_claims, &client_address)
            } else {
                0
            }
        } else {
            0
        }
    }

    #[view]
    public fun list_all_client_airdrop_amounts(): SimpleMap<address, u64> acquires AirdropManager, AdminStore {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        airdrop_manager.airdrop_amount_per_user
    }

    #[view]
    public fun list_all_client_wallet_balances(): SimpleMap<address, u64> acquires AirdropManager, AdminStore {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        airdrop_manager.airdrop_client_wallet
    }

    /// Check if a client has configured an airdrop amount
    #[view]
    public fun client_has_airdrop_config(client_address: address): bool acquires AirdropManager, AdminStore {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)
    }

    /// Helper function to remove a client configuration (admin only)
    public entry fun admin_remove_airdrop_config(
        admin: &signer,
        client_address: address
    ) acquires AirdropManager,AdminStore {
        let admin_addr = signer::address_of(admin);
        let admin_data = borrow_global_mut<AdminStore>(PHOTON_ADMIN);
        assert_admin(admin);
        let airdrop_manager = borrow_global_mut<AirdropManager>(get_resource_address());
                
        if (simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
            simple_map::remove(&mut airdrop_manager.airdrop_amount_per_user, &client_address);
        };
    }

    /// Get remaining claimable amount for a user from a specific client
    #[view]
    public fun get_remaining_claimable_amount(user_address: address, client_address: address): u64 acquires AirdropManager ,AdminStore {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        
        if (!simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
            return 0
        };

        let amount_per_user = *simple_map::borrow(&airdrop_manager.airdrop_amount_per_user, &client_address);
        let claimed_amount = get_claimed_amount(user_address, client_address);
        
        if (claimed_amount >= amount_per_user) {
            0
        } else {
            amount_per_user - claimed_amount
        }
    }

    /// Check if user has fully claimed their allocation from a client
    #[view]
    public fun is_airdrop_fully_claimed(user_address: address, client_address: address): bool acquires AirdropManager, AdminStore {
        get_remaining_claimable(user_address, client_address) == 0
    }

    /// Get user's claim status for a client (claimed, remaining, total)
    #[view]
    public fun get_user_airdrop_status(user_address: address, client_address: address): (u64, u64, u64) acquires AirdropManager, AdminStore {
        let claimed = get_claimed_amount(user_address, client_address);
        let remaining = get_remaining_claimable(user_address, client_address);
        let total = claimed + remaining;
        (claimed, remaining, total)
    }

    /// Check if user can claim a specific amount from a client
    #[view]
    public fun is_claim_amount_allowed(user_address: address, client_address: address, amount: u64): bool acquires AirdropManager, AdminStore {
        // First check if client is registered
        if (!PhotonClientModule::is_client_registered(client_address)) {
            return false
        };
        
        let remaining = get_remaining_claimable(user_address, client_address);
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        
        if (!simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address)) {
            return false
        };
        
        let client_balance = *simple_map::borrow(&airdrop_manager.airdrop_client_wallet, &client_address);
        
        amount > 0 && amount <= remaining && amount <= client_balance
    }

    /// Note: needs to update:- Check if client is registered in PhotonClientModule
    #[view]
    public fun is_client_registered_in_photon(client_address: address): bool {
        PhotonClientModule::is_client_registered(client_address)
    }

    /// Get comprehensive client information
    #[view]
    public fun get_airdrop_client_info(client_address: address): (bool, bool, u64, u64) acquires AirdropManager, AdminStore {
        let is_registered = PhotonClientModule::is_client_registered(client_address);
        let is_configured = is_client_configured(client_address);
        let airdrop_amount = get_airdrop_amount(client_address);
        let client_balance = get_client_balance(client_address);
        
        (is_registered, is_configured, airdrop_amount, client_balance)
    }
}