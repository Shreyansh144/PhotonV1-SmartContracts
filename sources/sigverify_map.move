module photon_admin::sigverify_map {
    use aptos_std::bcs;
    use aptos_std::ed25519;
    use aptos_std::hash;
    use aptos_std::vector;
    use aptos_std::table;

    /// Domain separation for signed payloads
    const DOMAIN_TAG: vector<u8> = b"PHOTON::sigverify::PHOTONV1";

    /// Example payload
    struct Order has copy, drop, store {
        maker: address,
        amount: u64,
        memo: vector<u8>,
    }

    /// Address allowlist resource
    struct Allowed has key {
        inner: table::Table<address, bool>,
    }

    /// Publish empty allowlist under the module publisher
    public entry fun init(creator: &signer) {
        assert!(!exists<Allowed>(signer::address_of(creator)), 0xA1);
        move_to(creator, Allowed { inner: table::new<address, bool>() });
    }

    /// Only the module account can mutate the list
    public entry fun add_allowed(creator: &signer, addr: address) {
        let me = signer::address_of(creator);
        assert!(exists<Allowed>(me), 0xA2);
        let a = borrow_global_mut<Allowed>(me);
        table::upsert(&mut a.inner, addr, true);
    }

    public entry fun remove_allowed(creator: &signer, addr: address) {
        let me = signer::address_of(creator);
        assert!(exists<Allowed>(me), 0xA3);
        let a = borrow_global_mut<Allowed>(me);
        if (table::contains(&a.inner, addr)) { table::remove(&mut a.inner, addr); }
    }

    /// Helper to build an order
    public fun new_order(maker: address, amount: u64, memo: vector<u8>): Order {
        Order { maker, amount, memo }
    }

    /// sha3_256(DOMAIN_TAG || bcs(order))
    public fun order_hash(order: &Order): vector<u8> {
        let order_bytes = bcs::to_bytes(order);
        let mut msg = DOMAIN_TAG;
        vector::append(&mut msg, order_bytes);
        hash::sha3_256(&msg)
    }

    /// Derive address from Ed25519 pubkey:
    /// auth_key = sha3_256(pubkey || 0x00), address = auth_key
    public fun address_from_ed25519_pubkey(pubkey: &vector<u8>): address {
        let mut pre = *pubkey;
        vector::push_back(&mut pre, 0u8); // scheme byte 0x00
        let auth_key = hash::sha3_256(&pre);
        // Convert 32 bytes -> address via BCS
        bcs::from_bytes<address>(&auth_key)
    }

    /// Read-only check: verify sig and membership in allowlist.
    /// Returns (is_valid_sig, derived_address, is_allowed)
    #[view]
    public fun verify_and_check_view(
        order: &Order,
        pubkey: vector<u8>,
        sig: vector<u8>,
        allowlist_holder: address
    ): (bool, address, bool) {
        let h = order_hash(order);
        let ok = ed25519::signature_verify(&sig, &pubkey, &h);
        let addr = address_from_ed25519_pubkey(&pubkey);

        let mut is_allowed = false;
        if (exists<Allowed>(allowlist_holder)) {
            let a = borrow_global<Allowed>(allowlist_holder);
            is_allowed = table::contains(&a.inner, addr);
        };

        (ok, addr, is_allowed)
    }

    /// Entry: aborts unless (valid sig) AND (derived address in allowlist)
    public entry fun verify_and_check_entry(
        _caller: &signer,
        maker: address,
        amount: u64,
        memo: vector<u8>,
        pubkey: vector<u8>,
        sig: vector<u8>,
        allowlist_holder: address
    ) {
        let order = Order { maker, amount, memo };
        let (ok, addr, allowed) = verify_and_check_view(&order, pubkey, sig, allowlist_holder);
        assert!(ok, 0xB1);
        assert!(allowed, 0xB2);
        // success path: continue your business logic here (e.g., accept order from addr)
        // ...
        let _ = addr; // suppress unused if not used further
    }
}
