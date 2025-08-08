module 0x1::client_registry {
    use std::signer;
    use std::vector;
    use std::string;
    use std::option;
    use std::error;
    use std::address;
    use std::timestamp;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_std::event::{Self, EventHandle};
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::managed_coin;

    // ====== ERROR CODES ======
    const E_NOT_ADMIN: u64 = 1;
    const E_ALREADY_REGISTERED: u64 = 2;
    const E_NOT_REGISTERED: u64 = 3;
    const E_INSUFFICIENT_BALANCE: u64 = 4;
    const E_INVALID_CLIENT_TYPE: u64 = 5;
    const E_INSUFFICIENT_FUND: u64 = 6;
    const E_CLIENT_MISMATCH: u64 = 7;
    const E_INVALID_OWNER: u64 = 8;
    const E_OWNER_NOT_HAVING_ENOUGH_COIN: u64 = 9;

    // ====== CLIENT TYPE ENUM (represented as u8) ======
    // 0 = Unknown
    // 1 = Merchant
    // 2 = Brand
    // 3 = Partner
    // 4 = Aggregator
    const CLIENT_TYPE_UNKNOWN: u8 = 0;
    const CLIENT_TYPE_MERCHANT: u8 = 1;
    const CLIENT_TYPE_BRAND: u8 = 2;
    const CLIENT_TYPE_PARTNER: u8 = 3;
    const CLIENT_TYPE_AGGREGATOR: u8 = 4;

    // ====== Admin resource ======
    struct Admin has key {
        owner: address,
    }

    // ====== Client resource stored at resource account ======
    struct ClientRegistry has key, store {
        client_name: vector<u8>,         // name bytes
        client_metadata: vector<u8>,     // metadata URI or hash as bytes
        client_wallet_address: address,      // on-chain address for the client's Aptos wallet
        created_at: u64,                 // unix timestamp
        active: bool,                    // active flag
        coin_type: address,              // address of PAT token module / coin marker (informational)
        total_tokens_earned: u128,
        total_tokens_spent: u128,
        client_type: u8,                 // enum value
        is_kyc_verified: bool,
        local_earn_onboarding_fee_percent: u8,
        local_spend_token_onboarding_client_fee_percent: u8,
        local_spend_token_facilitator_client_fee_percent: u8,
        signer_cap: account::SignerCapability, // Resource account signer capability
    }

    // Map to store client seeds and corresponding resource account address
    struct ClientCap has key {
        cap: account::SignerCapability,
        clientMap: SimpleMap<vector<u8>, address>,
        isProtocol: SimpleMap<address, bool>,
    }

    // ====== Event structures ======
    struct ClientRegisteredEvent has drop, store {
        client_seeds: vector<u8>,
        client_address: address,
        client_name: vector<u8>,
        client_type: u8,
        is_protocol: bool,
        timestamp: u64,
        admin_address: address,
    }

    struct TokenCreditedEvent has drop, store {
        client_seeds: vector<u8>,
        client_address: address,
        amount: u128,
        total_earned: u128,
        timestamp: u64,
        admin_address: address,
    }

    struct TokenDebitedEvent has drop, store {
        client_seeds: vector<u8>,
        client_address: address,
        amount: u128,
        total_spent: u128,
        timestamp: u64,
        admin_address: address,
    }

    struct ClientStatusUpdatedEvent has drop, store {
        client_seeds: vector<u8>,
        client_address: address,
        field_name: vector<u8>,
        old_value: vector<u8>,
        new_value: vector<u8>,
        timestamp: u64,
        admin_address: address,
    }

    // Global event store
    struct ClientRegistryEvents has key {
        client_registered_events: EventHandle<ClientRegisteredEvent>,
        token_credited_events: EventHandle<TokenCreditedEvent>,
        token_debited_events: EventHandle<TokenDebitedEvent>,
        client_status_updated_events: EventHandle<ClientStatusUpdatedEvent>,
    }

    // ====== Helpers ======
    fun assert_admin(caller: &signer) {
        let owner_addr = signer::address_of(caller);
        let admin_ref = borrow_global<Admin>(owner_addr);
        if (admin_ref.owner != owner_addr) {
            abort E_NOT_ADMIN;
        }
    }

    fun get_client_signer_address(): address acquires ClientCap {
        let client_cap = &borrow_global<ClientCap>(@0x1).cap;
        let client_signer = &account::create_signer_with_capability(client_cap);
        let client_signer_address = signer::address_of(client_signer);
        client_signer_address
    }

    // // ====== Initialize admin and events ======
    // public entry fun initialize_admin(admin: &signer) {
    //     let admin_addr = signer::address_of(admin);
    //     assert!(admin_addr == @0x1, error::invalid_argument(E_INVALID_OWNER));
        
    //     if (!exists<Admin>(admin_addr)) {
    //         move_to(admin, Admin { owner: admin_addr })
    //     };

    //     // Create resource account for client registry management
    //     let (client_signer, client_cap) = account::create_resource_account(admin, b"client_registry");
    //     let client_signer_address = signer::address_of(&client_signer);

    //     if (!exists<ClientCap>(@0x1)) {
    //         move_to(admin, ClientCap { 
    //             cap: client_cap,
    //             clientMap: simple_map::create(),
    //             isProtocol: simple_map::create()
    //         })
    //     };

    //     if (!exists<ClientRegistryEvents>(client_signer_address)) {
    //         move_to(&client_signer, ClientRegistryEvents {
    //             client_registered_events: account::new_event_handle<ClientRegisteredEvent>(&client_signer),
    //             token_credited_events: account::new_event_handle<TokenCreditedEvent>(&client_signer),
    //             token_debited_events: account::new_event_handle<TokenDebitedEvent>(&client_signer),
    //             client_status_updated_events: account::new_event_handle<ClientStatusUpdatedEvent>(&client_signer),
    //         });
    //     };
    // }

    // ====== Register client with resource account ======
    public entry fun register_client(
        admin: &signer,
        name: vector<u8>,
        metadata: vector<u8>,
        client_type: u8,
        seeds: vector<u8>,
        isProtocol: bool
    ) acquires ClientCap, ClientRegistryEvents {
        // Only admin may register
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        
        // Create resource account for the client
        let (client_account, client_cap) = account::create_resource_account(admin, seeds);
        let client_address = signer::address_of(&client_account);
        
        // Initialize ClientCap if it doesn't exist
        if (!exists<ClientCap>(admin_addr)) {
            move_to(admin, ClientCap { 
                clientMap: simple_map::create(),
                isProtocol: simple_map::create()
            })
        };
        
        // Store the mapping of seeds to resource account address
        let maps = borrow_global_mut<ClientCap>(admin_addr);
        simple_map::add(&mut maps.clientMap, seeds, client_address);
        simple_map::add(&mut maps.isProtocol, client_address, isProtocol);
        
        // Create client registry at the resource account
        let client_signer_from_cap = account::create_signer_with_capability(&client_cap);
        let now = timestamp::now_seconds();
        
        move_to(&client_signer_from_cap, ClientRegistry {
            client_name: name,
            client_metadata: metadata,
            client_wallet_address: client_address,
            created_at: now,
            active: true,
            coin_type: @0x1, // Default coin type address, can be updated later
            total_tokens_earned: 0,
            total_tokens_spent: 0,
            client_type: client_type,
            is_kyc_verified: false,
            local_earn_onboarding_fee_percent: 0,
            local_spend_token_onboarding_client_fee_percent: 0,
            local_spend_token_facilitator_client_fee_percent: 0,
            signer_cap: client_cap,
        });

        // Emit registration event
        let client_signer_address = get_client_signer_address();
        let events = borrow_global_mut<ClientRegistryEvents>(client_signer_address);
        event::emit_event<ClientRegisteredEvent>(
            &mut events.client_registered_events,
            ClientRegisteredEvent {
                client_seeds: seeds,
                client_address,
                client_name: name,
                client_type,
                is_protocol: isProtocol,
                timestamp: now,
                admin_address: admin_addr,
            },
        );
    }

    // ====== View client ======
    public fun get_client(admin: &signer, client_seeds: vector<u8>): ClientRegistry acquires ClientCap {
        // admin-only view for now
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<ClientCap>(admin_addr);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let client_addr = option::extract(&mut client_addr_opt);
        *borrow_global<ClientRegistry>(client_addr)
    }

    // ====== Update simple flags & metadata ======
    public entry fun set_active(admin: &signer, client_seeds: vector<u8>, active: bool) acquires ClientCap, ClientRegistryEvents {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<ClientCap>(@0x1);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let client_addr = option::extract(&mut client_addr_opt);
        let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
        client_ref.active = active;

        // Emit status update event
        let client_signer_address = get_client_signer_address();
        let events = borrow_global_mut<ClientRegistryEvents>(client_signer_address);
        event::emit_event<ClientStatusUpdatedEvent>(
            &mut events.client_status_updated_events,
            ClientStatusUpdatedEvent {
                client_seeds,
                client_address: client_addr,
                field_name: b"active",
                old_value,
                new_value,
                timestamp: timestamp::now_seconds(),
                admin_address: admin_addr,
            },
        );
    }

    public entry fun set_kyc(admin: &signer, client_seeds: vector<u8>, verified: bool) acquires ClientCap, ClientRegistryEvents {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<ClientCap>(admin_addr);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let client_addr = option::extract(&mut client_addr_opt);
        let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
        client_ref.is_kyc_verified = verified;

        // Emit status update event
        let client_signer_address = get_client_signer_address();
        let events = borrow_global_mut<ClientRegistryEvents>(client_signer_address);
        event::emit_event<ClientStatusUpdatedEvent>(
            &mut events.client_status_updated_events,
            ClientStatusUpdatedEvent {
                client_seeds,
                client_address: client_addr,
                field_name: b"kyc_verified",
                old_value,
                new_value,
                timestamp: timestamp::now_seconds(),
                admin_address: admin_addr,
            },
        );
    }

    public entry fun set_local_fees(
        admin: &signer,
        client_seeds: vector<u8>,
        earn_fee: u8,
        spend_onboarding_fee: u8,
        spend_facilitator_fee: u8
    ) acquires ClientCap, ClientRegistryEvents {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<ClientCap>(admin_addr);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let client_addr = option::extract(&mut client_addr_opt);
        let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
        
        // Update fees
        client_ref.local_earn_onboarding_fee_percent = earn_fee;
        client_ref.local_spend_token_onboarding_client_fee_percent = spend_onboarding_fee;
        client_ref.local_spend_token_facilitator_client_fee_percent = spend_facilitator_fee;

        // Emit status update event
        let client_signer_address = get_client_signer_address();
        let events = borrow_global_mut<ClientRegistryEvents>(client_signer_address);
        event::emit_event<ClientStatusUpdatedEvent>(
            &mut events.client_status_updated_events,
            ClientStatusUpdatedEvent {
                client_seeds,
                client_address: client_addr,
                field_name: b"local_fees",
                old_value: b"",
                new_value: b"updated",
                timestamp: timestamp::now_seconds(),
                admin_address: admin_addr,
            },
        );
    }

    // ====== Token accounting helpers with coin transfer ======
    // Credit earned tokens to a client with actual coin transfer
    public entry fun credit_tokens<CoinType>(
        admin: &signer, 
        client_seeds: vector<u8>, 
        amount: u128
    ) acquires ClientCap, ClientRegistryEvents {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        
        // Check admin has enough coins
        assert!(coin::balance<CoinType>(admin_addr) >= amount, error::invalid_argument(E_OWNER_NOT_HAVING_ENOUGH_COIN));
        
        let maps = borrow_global<ClientCap>(@0x1);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let client_addr = option::extract(&mut client_addr_opt);
        let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
        
        // Transfer coins from admin to client resource account
        coin::transfer<CoinType>(admin, client_addr, amount);
        
        // Update accounting
        client_ref.total_tokens_earned = client_ref.total_tokens_earned + amount;

        // Emit credit event
        let client_signer_address = get_client_signer_address();
        let events = borrow_global_mut<ClientRegistryEvents>(client_signer_address);
        event::emit_event<TokenCreditedEvent>(
            &mut events.token_credited_events,
            TokenCreditedEvent {
                client_seeds,
                client_address: client_addr,
                amount,
                total_earned: client_ref.total_tokens_earned,
                timestamp: timestamp::now_seconds(),
                admin_address: admin_addr,
            },
        );
    }

    // Debit tokens when client spends (transfer back to admin)
    public entry fun debit_tokens<CoinType>(
        admin: &signer, 
        client_seeds: vector<u8>, 
        amount: u128
    ) acquires ClientCap, ClientRegistryEvents {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<ClientCap>(@0x1);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let client_addr = option::extract(&mut client_addr_opt);
        let client_ref = borrow_global_mut<ClientRegistry>(client_addr);
        
        if (client_ref.total_tokens_earned < client_ref.total_tokens_spent + amount) {
            abort E_INSUFFICIENT_BALANCE;
        };

        // Get client signer to transfer coins back to admin
        let client_signer = account::create_signer_with_capability(&client_ref.signer_cap);
        coin::transfer<CoinType>(&client_signer, admin_addr, amount);
        
        client_ref.total_tokens_spent = client_ref.total_tokens_spent + amount;

        // Emit debit event
        let client_signer_address = get_client_signer_address();
        let events = borrow_global_mut<ClientRegistryEvents>(client_signer_address);
        event::emit_event<TokenDebitedEvent>(
            &mut events.token_debited_events,
            TokenDebitedEvent {
                client_seeds,
                client_address: client_addr,
                amount,
                total_spent: client_ref.total_tokens_spent,
                timestamp: timestamp::now_seconds(),
                admin_address: admin_addr,
            },
        );
    }

    // ====== Convenience: check if registered ======
    public fun is_registered(admin: &signer, client_seeds: vector<u8>): bool acquires ClientCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<ClientCap>(admin_addr);
        simple_map::contains_key(&maps.clientMap, &client_seeds)
    }

    // ====== Remove client (admin only) ======
    public entry fun remove_client(admin: &signer, client_seeds: vector<u8>) acquires ClientCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global_mut<ClientCap>(admin_addr);
        
        if (!simple_map::contains_key(&maps.clientMap, &client_seeds)) {
            abort E_NOT_REGISTERED;
        };
        
        let client_addr = simple_map::remove(&mut maps.clientMap, &client_seeds);
        simple_map::remove(&mut maps.isProtocol, &client_addr);
        
        // Extract and destroy the client registry
        let ClientRegistry {
            client_name: _,
            client_metadata: _,
            client_wallet_address: _,
            created_at: _,
            active: _,
            coin_type: _,
            total_tokens_earned: _,
            total_tokens_spent: _,
            client_type: _,
            is_kyc_verified: _,
            local_earn_onboarding_fee_percent: _,
            local_spend_token_onboarding_client_fee_percent: _,
            local_spend_token_facilitator_client_fee_percent: _,
            signer_cap: _,
        } = move_from<ClientRegistry>(client_addr);
    }

    // ====== Get client resource account address ======
    public fun get_client_resource_address(admin: &signer, client_seeds: vector<u8>): address acquires ClientCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<ClientCap>(admin_addr);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        option::extract(&mut client_addr_opt)
    }

    // ====== Check if client is protocol ======
    public fun is_protocol_client(admin: &signer, client_seeds: vector<u8>): bool acquires ClientCap {
        assert_admin(admin);
        let admin_addr = signer::address_of(admin);
        let maps = borrow_global<ClientCap>(admin_addr);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let client_addr = option::extract(&mut client_addr_opt);
        simple_map::contains_key(&maps.isProtocol, &client_addr) && 
        *simple_map::borrow(&maps.isProtocol, &client_addr)
    }

    // ====== Get client balance ======
    public fun get_client_balance<CoinType>(admin: &signer, client_seeds: vector<u8>): u128 acquires ClientCap {
        assert_admin(admin);
        let maps = borrow_global<ClientCap>(@0x1);
        let client_addr_opt = simple_map::get(&maps.clientMap, &client_seeds);
        if (!option::is_some(&client_addr_opt)) {
            abort E_NOT_REGISTERED;
        };
        let client_addr = option::extract(&mut client_addr_opt);
        coin::balance<CoinType>(client_addr)
    }
}
