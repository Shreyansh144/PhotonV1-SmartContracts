module airdrop_manager::airdrop_manager {
    use std::signer;
    use std::error;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::object;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_std::string::{Self, String};

    // Error codes
    const E_INVALID_OWNER: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_ALREADY_CLAIMED: u64 = 3;
    const E_CLIENT_NOT_CONFIGURED: u64 = 4;
    const E_INVALID_ATTESTATION: u64 = 5;
    const E_NOT_AUTHORIZED: u64 = 6;

    // Admin address - replace with your admin address
    const AIRDROP_ADMIN: address = @0x123; // Replace with actual admin address

    /// Capabilities stored in resource account
    struct Capabilities has key {
        admin_signer_cap: account::SignerCapability,
    }

    /// Main airdrop configuration and state
    struct AirdropManager has key {
        // Configuration: client address -> amount per user
        airdrop_amount_per_user: SimpleMap<address, u64>,
        // Track claims: user address -> (client address -> claimed amount)
        airdrop_claimed: SimpleMap<address, SimpleMap<address, u64>>,
        // Client wallet balances: client address -> available balance
        airdrop_client_wallet: SimpleMap<address, u64>,
        // Token metadata for PAT token
        token_metadata: object::Object<Metadata>,
        // Admin address
        admin: address,
        // Resource account address
        resource_account_address: address,
    }

    /// Initialize the airdrop manager with resource account
    public entry fun init_airdrop_manager(admin: &signer, token_metadata: object::Object<Metadata>) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == AIRDROP_ADMIN, error::invalid_argument(E_INVALID_OWNER));

        // Create resource account for airdrop manager
        let (airdrop_resource_signer, airdrop_cap) = account::create_resource_account(admin, b"airdrop_manager_v1");
        let resource_addr = signer::address_of(&airdrop_resource_signer);

        // Store capabilities in resource account
        move_to(&airdrop_resource_signer, Capabilities {
            admin_signer_cap: airdrop_cap,
        });

        // Initialize airdrop manager state
        move_to(&airdrop_resource_signer, AirdropManager {
            airdrop_amount_per_user: simple_map::create(),
            airdrop_claimed: simple_map::create(),
            airdrop_client_wallet: simple_map::create(),
            token_metadata,
            admin: admin_addr,
            resource_account_address: resource_addr,
        });

        // Ensure primary store exists for the resource account
        primary_fungible_store::ensure_primary_store_exists(resource_addr, token_metadata);
    }

    /// Update airdrop amount configuration for a client
    public entry fun update_amount(
        admin: &signer,
        client_address: address,
        amount_per_user: u64
    ) acquires AirdropManager {
        let admin_addr = signer::address_of(admin);
        let airdrop_manager = borrow_global_mut<AirdropManager>(get_resource_address());
        
        assert!(admin_addr == airdrop_manager.admin, error::permission_denied(E_NOT_AUTHORIZED));
        
        if (simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
            let amount_ref = simple_map::borrow_mut(&mut airdrop_manager.airdrop_amount_per_user, &client_address);
            *amount_ref = amount_per_user;
        } else {
            simple_map::add(&mut airdrop_manager.airdrop_amount_per_user, client_address, amount_per_user);
        };
    }

    /// Add money to client wallet
    public entry fun add_money(
        admin: &signer,
        client_address: address,
        quantity: u64
    ) acquires AirdropManager, Capabilities {
        let admin_addr = signer::address_of(admin);
        let resource_addr = get_resource_address();
        let airdrop_manager = borrow_global_mut<AirdropManager>(resource_addr);
        
        assert!(admin_addr == airdrop_manager.admin, error::permission_denied(E_NOT_AUTHORIZED));

        // Get current balance or initialize to 0
        let current_balance = if (simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address)) {
            *simple_map::borrow(&airdrop_manager.airdrop_client_wallet, &client_address)
        } else {
            0
        };

        let new_balance = current_balance + quantity;

        // Update or add client wallet balance
        if (simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address)) {
            let balance_ref = simple_map::borrow_mut(&mut airdrop_manager.airdrop_client_wallet, &client_address);
            *balance_ref = new_balance;
        } else {
            simple_map::add(&mut airdrop_manager.airdrop_client_wallet, client_address, new_balance);
        };

        // Transfer tokens from admin to resource account
        let capabilities = borrow_global<Capabilities>(resource_addr);
        let resource_signer = account::create_signer_with_capability(&capabilities.admin_signer_cap);
        
        primary_fungible_store::transfer(
            admin,
            primary_fungible_store::primary_store(resource_addr, airdrop_manager.token_metadata),
            quantity
        );
    }

    /// Claim airdrop tokens
    public entry fun claim_airdrop(
        user: &signer,
        client_address: address,
        attestation: vector<u8> // Simple attestation for now - can be enhanced
    ) acquires AirdropManager, Capabilities {
        let user_addr = signer::address_of(user);
        let resource_addr = get_resource_address();
        let airdrop_manager = borrow_global_mut<AirdropManager>(resource_addr);

        // Verify attestation (simplified - you can implement more complex verification)
        assert!(vector::length(&attestation) > 0, error::invalid_argument(E_INVALID_ATTESTATION));

        // Check if client is configured
        assert!(
            simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address),
            error::invalid_argument(E_CLIENT_NOT_CONFIGURED)
        );

        let amount_per_user = *simple_map::borrow(&airdrop_manager.airdrop_amount_per_user, &client_address);

        // Get user's claimed amount for this client
        let claimed_amount = if (simple_map::contains_key(&airdrop_manager.airdrop_claimed, &user_addr)) {
            let user_claims = simple_map::borrow(&airdrop_manager.airdrop_claimed, &user_addr);
            if (simple_map::contains_key(user_claims, &client_address)) {
                *simple_map::borrow(user_claims, &client_address)
            } else {
                0
            }
        } else {
            0
        };

        // Check if user has already claimed the full amount
        assert!(claimed_amount < amount_per_user, error::invalid_argument(E_ALREADY_CLAIMED));

        let amount_to_be_claimed = amount_per_user - claimed_amount;

        // Check client wallet has sufficient balance
        assert!(
            simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address),
            error::invalid_state(E_INSUFFICIENT_BALANCE)
        );

        let client_balance = *simple_map::borrow(&airdrop_manager.airdrop_client_wallet, &client_address);
        assert!(client_balance >= amount_to_be_claimed, error::invalid_state(E_INSUFFICIENT_BALANCE));

        // Update client wallet balance
        let client_balance_ref = simple_map::borrow_mut(&mut airdrop_manager.airdrop_client_wallet, &client_address);
        *client_balance_ref = client_balance - amount_to_be_claimed;

        // Update user claimed amount
        if (!simple_map::contains_key(&airdrop_manager.airdrop_claimed, &user_addr)) {
            simple_map::add(&mut airdrop_manager.airdrop_claimed, user_addr, simple_map::create<address, u64>());
        };

        let user_claims = simple_map::borrow_mut(&mut airdrop_manager.airdrop_claimed, &user_addr);
        if (simple_map::contains_key(user_claims, &client_address)) {
            let claimed_ref = simple_map::borrow_mut(user_claims, &client_address);
            *claimed_ref = claimed_amount + amount_to_be_claimed;
        } else {
            simple_map::add(user_claims, client_address, amount_to_be_claimed);
        };

        // Transfer tokens to user
        let capabilities = borrow_global<Capabilities>(resource_addr);
        let resource_signer = account::create_signer_with_capability(&capabilities.admin_signer_cap);

        primary_fungible_store::transfer(
            &resource_signer,
            primary_fungible_store::primary_store(user_addr, airdrop_manager.token_metadata),
            amount_to_be_claimed
        );
    }

    /// Get resource account address
    public fun get_resource_address(): address {
        // This should be computed based on your actual admin address and seed
        // For now, using a placeholder - replace with actual computation
        account::create_resource_address(&AIRDROP_ADMIN, b"airdrop_manager_v1")
    }

    /// View functions for querying state
    #[view]
    public fun get_airdrop_amount(client_address: address): u64 acquires AirdropManager {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        if (simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
            *simple_map::borrow(&airdrop_manager.airdrop_amount_per_user, &client_address)
        } else {
            0
        }
    }

    #[view]
    public fun get_client_balance(client_address: address): u64 acquires AirdropManager {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        if (simple_map::contains_key(&airdrop_manager.airdrop_client_wallet, &client_address)) {
            *simple_map::borrow(&airdrop_manager.airdrop_client_wallet, &client_address)
        } else {
            0
        }
    }

    #[view]
    public fun get_claimed_amount(user_address: address, client_address: address): u64 acquires AirdropManager {
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
    public fun get_all_airdrop_amounts(): SimpleMap<address, u64> acquires AirdropManager {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        airdrop_manager.airdrop_amount_per_user
    }

    #[view]
    public fun get_all_client_balances(): SimpleMap<address, u64> acquires AirdropManager {
        let airdrop_manager = borrow_global<AirdropManager>(get_resource_address());
        airdrop_manager.airdrop_client_wallet
    }

    /// Initialize example configuration (for testing)
    public entry fun initialize_example_config(admin: &signer) acquires AirdropManager {
        let fliq_address = @0xf11c; // Replace with actual fliq address
        let fan_craze_address = @0xfac5; // Replace with actual fanCraze address

        // Set airdrop amounts
        update_amount(admin, fliq_address, 10);
        update_amount(admin, fan_craze_address, 5);
    }

    /// Helper function to remove a client configuration (admin only)
    public entry fun remove_client_config(
        admin: &signer,
        client_address: address
    ) acquires AirdropManager {
        let admin_addr = signer::address_of(admin);
        let airdrop_manager = borrow_global_mut<AirdropManager>(get_resource_address());
        
        assert!(admin_addr == airdrop_manager.admin, error::permission_denied(E_NOT_AUTHORIZED));
        
        if (simple_map::contains_key(&airdrop_manager.airdrop_amount_per_user, &client_address)) {
            simple_map::remove(&mut airdrop_manager.airdrop_amount_per_user, &client_address);
        };
    }

    /// Get remaining claimable amount for a user from a specific client
    #[view]
    public fun get_remaining_claimable(user_address: address, client_address: address): u64 acquires AirdropManager {
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
}