module photon_airdrop::AirdropManager {
    use std::signer;
    use std::vector;
    use std::error;
    use std::string;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::event;
    use aptos_framework::primary_fungible_store;


    /// Error codes
    const E_INVALID_OWNER: u64 = 100;
    const E_NO_BALANCE: u64 = 101;
    const E_ALREADY_CLAIMED: u64 = 102;
    const E_INSUFFICIENT_CLIENT_BALANCE: u64 = 103;

    /// This is your project owner address
    const PHOTON_ADMIN: address = @photon_admin;

    /// Resource account AirdropManager
    struct AirdropManager has key {
        admin_signer_cap: account::SignerCapability,
    }

    /// Store airdrop configuration
    struct AirdropConfig has key {
        amount_per_user: SimpleMap<address, u64>, // client -> per user airdrop amount
        claimed: SimpleMap<address, SimpleMap<address, u64>>, // user -> (client -> claimed_amount)
        client_wallet: SimpleMap<address, u64>, // client -> remaining balance
    }

    /// Initialize the AirdropManager with a resource account
    public entry fun init_airdrop_manager(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == PHOTON_ADMIN, error::invalid_argument(E_INVALID_OWNER));

        // Create resource account
        let (airdrop_manager, airdrop_cap) = account::create_resource_account(admin, b"airdrop_manager_test_1");
        let airdrop_manager_addr = signer::address_of(&airdrop_manager);

        // Create signer from capability
        let airdrop_signer_from_cap = account::create_signer_with_capability(&airdrop_cap);

        // Move capability to resource account
        move_to(&airdrop_signer_from_cap, AirdropManager { admin_signer_cap: airdrop_cap });

        // Initialize empty config in resource account
        move_to(&airdrop_signer_from_cap, AirdropConfig {
            amount_per_user: SimpleMap::new<address, u64>(),
            claimed: SimpleMap::new<address, SimpleMap<address, u64>>(),
            client_wallet: SimpleMap::new<address, u64>(),
        });
        primary_fungible_store::ensure_primary_store_exists(admin_addr, get_metadata());
    }

    /// Add/Update per-user airdrop amount for a client
    public entry fun update_amount(resource_admin: &signer, client: address, amount: u64) {
        let cfg = borrow_global_mut<AirdropConfig>(signer::address_of(resource_admin));
        SimpleMap::upsert(&mut cfg.amount_per_user, client, amount);
    }

    /// Add money to a client's airdrop wallet
    public entry fun add_money(resource_admin: &signer, client: address, amount: u64) {
        let cfg = borrow_global_mut<AirdropConfig>(signer::address_of(resource_admin));
        let current = SimpleMap::get(&cfg.client_wallet, client).unwrap_or(0);
        SimpleMap::upsert(&mut cfg.client_wallet, client, current + amount);
    }

    /// Claim airdrop for a user from a specific client
    // public entry fun claim_airdrop(user: &signer, client: address /* attestation */) {
    //     let cfg = borrow_global_mut<AirdropConfig>(get_airdrop_manager_address());

    //     let user_addr = signer::address_of(user);

    //     // Get amount per user
    //     let per_user_amount = SimpleMap::get(&cfg.amount_per_user, client).unwrap_or(0);
    //     assert!(per_user_amount > 0, error::invalid_argument(E_NO_BALANCE));

    //     // Get already claimed amount
    //     let user_claims_map = SimpleMap::get_mut(&mut cfg.claimed, user_addr)
    //         .unwrap_or_else(|| {
    //             let new_map = SimpleMap::new<address, u64>();
    //             SimpleMap::upsert(&mut cfg.claimed, user_addr, new_map);
    //             SimpleMap::get_mut(&mut cfg.claimed, user_addr).unwrap()
    //         });

    //     let already_claimed = SimpleMap::get(user_claims_map, client).unwrap_or(0);
    //     assert!(already_claimed < per_user_amount, error::invalid_argument(E_ALREADY_CLAIMED));

    //     // Amount to be claimed
    //     let claim_amount = per_user_amount - already_claimed;

    //     // Check client balance
    //     let client_balance = SimpleMap::get(&cfg.client_wallet, client).unwrap_or(0);
    //     assert!(client_balance >= claim_amount, error::invalid_argument(E_INSUFFICIENT_CLIENT_BALANCE));

    //     // Deduct from client wallet
    //     SimpleMap::upsert(&mut cfg.client_wallet, client, client_balance - claim_amount);

    //     // Update claimed amount
    //     SimpleMap::upsert(user_claims_map, client, already_claimed + claim_amount);

    //     // Transfer PAT tokens (replace aptos_coin::AptosCoin with your token type)
    //     coin::transfer<AptosCoin>(resource_admin_signer(), user_addr, claim_amount);
    // }
    public entry fun claim_airdrop(user: &signer, client: address /* attestation */) {
    let cfg = borrow_global_mut<AirdropConfig>(get_airdrop_manager_address());

    let user_addr = signer::address_of(user);

    // Get amount per user
    let per_user_amount = SimpleMap::get(&cfg.amount_per_user, client).unwrap_or(0);
    assert!(per_user_amount > 0, error::invalid_argument(E_NO_BALANCE));

    // Get already claimed amount
    let user_claims_map = SimpleMap::get_mut(&mut cfg.claimed, user_addr)
        .unwrap_or_else(|| {
            let new_map = SimpleMap::new<address, u64>();
            SimpleMap::upsert(&mut cfg.claimed, user_addr, new_map);
            SimpleMap::get_mut(&mut cfg.claimed, user_addr).unwrap()
        });

    let already_claimed = SimpleMap::get(user_claims_map, client).unwrap_or(0);
    assert!(already_claimed < per_user_amount, error::invalid_argument(E_ALREADY_CLAIMED));

    // Amount to be claimed
    let claim_amount = per_user_amount - already_claimed;

    // Check client balance
    let client_balance = SimpleMap::get(&cfg.client_wallet, client).unwrap_or(0);
    assert!(client_balance >= claim_amount, error::invalid_argument(E_INSUFFICIENT_CLIENT_BALANCE));

    // Deduct from client wallet
    SimpleMap::upsert(&mut cfg.client_wallet, client, client_balance - claim_amount);

    // Update claimed amount
    SimpleMap::upsert(user_claims_map, client, already_claimed + claim_amount);

    // ====== Your custom logic here ======
    let resource_signer = resource_admin_signer();
    primary_fungible_store::ensure_primary_store_exists(user_addr, get_metadata());

    // Debit airdrop manager wallet
    debit_airdrop_manager_wallet(&resource_signer, claim_amount);

    // Credit user
    credit_tokens(user, claim_amount);
}


    /// Helper — returns the AirdropManager's resource account address
    public fun get_airdrop_manager_address(): address {
        @airdrop_manager_resource_account // replace with actual
    }

    /// Helper — create signer from stored capability
    public fun resource_admin_signer(): signer {
        let caps = borrow_global<AirdropManager>(get_airdrop_manager_address());
        account::create_signer_with_capability(&caps.admin_signer_cap)
    }
}
