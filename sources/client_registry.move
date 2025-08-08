module PhotonResourceAddress::client_registry {
    use std::vector;
    use std::signer;
    use std::timestamp;
    use PhotonResourceAddress::common_utils;
    use aptos_std::simple_map::{Self, SimpleMap};


    struct ClientData has copy, drop, store {
        client_name: vector<u8>,
        client_metadata: vector<u8>,
        client_wallet: address,
        created_at: u64,
        active: bool,
        wallet_balance: u128, // numeric PAT
        // Fee fields (kept as names, not used for calc)
        global_earn_token_onboarding_client_fees: u8,
        global_spend_token_onboarding_client_fees: u8,
        global_spend_token_facilitator_client_fees: u8,
    }

    struct ClientRegistry {
        owner: address, // admin who created
        clients: SimpleMap< vector<u8>,address>, // mapping client_address -> ClientData
        created_at: u64,
    }

    public entry fun initialize(admin: &signer) {
        let addr = signer::address_of(admin);
        assert!(!exists<ClientRegistry>(addr), 0);
        move_to(admin, ClientRegistry {
            owner: addr,
            clients: vector::empty(),
            created_at: timestamp::now_seconds(),
        });
    }

    /// Only admin (owner of this resource) should call to register a new client
    public entry fun register_client(admin: &signer, client_addr: address, client_name: vector<u8>, client_metadata: vector<u8>, client_wallet: address) acquires ClientRegistry {
        let owner_addr = signer::address_of(admin);
        assert!(exists<ClientRegistry>(owner_addr), 1);
        let reg = borrow_global_mut<ClientRegistry>(owner_addr);
        assert!(reg.owner == owner_addr, 2);

        // ensure not already registered
        let idx_opt = common_utils::index_of_addr(&reg.clients, client_addr);
        assert!(option::is_none(&idx_opt), 3);

        let data = ClientData {
            client_name,
            client_metadata,
            client_wallet,
            created_at: timestamp::now_seconds(),
            active: true,
            wallet_balance: 0u128,
            global_earn_token_onboarding_client_fees: 0,
            global_spend_token_onboarding_client_fees: 0,
            global_spend_token_facilitator_client_fees: 0,
        };
        vector::push_back(&mut reg.clients, (client_addr, data));
    }

    public entry fun update_client_status(admin: &signer, client_addr: address, active: bool) acquires ClientRegistry {
        let owner_addr = signer::address_of(admin);
        assert!(exists<ClientRegistry>(owner_addr), 4);
        let reg = borrow_global_mut<ClientRegistry>(owner_addr);
        let idx_opt = common_utils::index_of_addr(&reg.clients, client_addr);
        assert!(option::is_some(&idx_opt), 5);
        let idx = option::extract(idx_opt);
        let pair_ref = common_utils::borrow_by_index(&reg.clients, idx);
        // pair_ref is &(address, ClientData) but we need mutable; do a remove+push pattern for simplicity
        let (_, data) = *pair_ref;
        // replace mutably:
        common_utils::remove_by_index(&mut reg.clients, idx);
        let new_data = ClientData {
            client_name: data.client_name,
            client_metadata: data.client_metadata,
            client_wallet: data.client_wallet,
            created_at: data.created_at,
            active,
            wallet_balance: data.wallet_balance,
            global_earn_token_onboarding_client_fees: data.global_earn_token_onboarding_client_fees,
            global_spend_token_onboarding_client_fees: data.global_spend_token_onboarding_client_fees,
            global_spend_token_facilitator_client_fees: data.global_spend_token_facilitator_client_fees,
        };
        vector::push_back(&mut reg.clients, (client_addr, new_data));
    }

    /// Credit client's numeric wallet balance (simulates mint/transfer). Admin-only for now.
    public entry fun credit_client_balance(admin: &signer, client_addr: address, amount: u128) acquires ClientRegistry {
        let owner_addr = signer::address_of(admin);
        assert!(exists<ClientRegistry>(owner_addr), 6);
        let reg = borrow_global_mut<ClientRegistry>(owner_addr);
        let idx_opt = common_utils::index_of_addr(&reg.clients, client_addr);
        assert!(option::is_some(&idx_opt), 7);
        let idx = option::extract(idx_opt);
        let (a, mut data) = *common_utils::borrow_by_index(&reg.clients, idx);
        common_utils::remove_by_index(&mut reg.clients, idx);
        data.wallet_balance = data.wallet_balance + amount;
        vector::push_back(&mut reg.clients, (client_addr, data));
    }

    /// Debit client's numeric wallet balance. Used by SpendManager etc (access controlled externally).
    public fun debit_client_balance(reg_owner: address, client_addr: address, amount: u128) acquires ClientRegistry {
        assert!(exists<ClientRegistry>(reg_owner), 8);
        let reg = borrow_global_mut<ClientRegistry>(reg_owner);
        let idx_opt = common_utils::index_of_addr(&reg.clients, client_addr);
        assert!(option::is_some(&idx_opt), 9);
        let idx = option::extract(idx_opt);
        let (a, mut data) = *common_utils::borrow_by_index(&reg.clients, idx);
        common_utils::remove_by_index(&mut reg.clients, idx);
        assert!(data.wallet_balance >= amount, 10);
        data.wallet_balance = data.wallet_balance - amount;
        vector::push_back(&mut reg.clients, (client_addr, data));
    }

    /// Read client wallet numeric balance (view)
    public fun client_wallet_balance(reg_owner: address, client_addr: address): u128 acquires ClientRegistry {
        assert!(exists<ClientRegistry>(reg_owner), 11);
        let reg = borrow_global<ClientRegistry>(reg_owner);
        let idx_opt = common_utils::index_of_addr(&reg.clients, client_addr);
        assert!(option::is_some(&idx_opt), 12);
        let idx = option::extract(idx_opt);
        let (_, data) = *common_utils::borrow_by_index(&reg.clients, idx);
        data.wallet_balance
    }
}
