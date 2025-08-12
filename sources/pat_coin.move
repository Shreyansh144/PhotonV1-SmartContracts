/// A 2-in-1 module that combines managed_fungible_asset and coin_example into one module that when deployed, the
/// deployer will be creating a new managed fungible asset with the hardcoded supply config, name, symbol, and decimals.
/// The address of the asset can be obtained via get_metadata(). As a simple version, it only deals with primary stores.
module photon_pat_token::pat_coin{
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::function_info;
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::event;
    use std::error;
    use std::signer;
    use std::string::{Self, utf8};
    use std::option;

    const PATCoin: address = @photon_pat_token;


    /// Only fungible asset metadata owner can make changes.
    const ENOT_OWNER: u64 = 1;
    /// The PAT coin is paused.
    const EPAUSED: u64 = 2;

    const EINVALID_ASSET: u64 = 3;

     /// Caller is not authorized to make this call
    const EUNAUTHORIZED: u64 = 4;


    const PAT_NAME: vector<u8> = b"PAT Coin";
    const PAT_SYMBOL: vector<u8> = b"PAt";
    const PAT_DECIMALS: u8 = 8;
    const PROJECT_URI: vector<u8> = b"http://example.com";
    const ICON_URI: vector<u8> = b"http://example.com/favicon.ico";
    

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Hold refs to control the minting, transfer and burning of fungible assets.
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        admin: address,
        pending_admin: address,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Global state to pause the PAT coin.
    /// OPTIONAL
    struct State has key {
        paused: bool,
    }

    #[event]
    struct Mint has drop, store {
        to: address,
        amount: u64,
    }

    #[event]
    struct Burn has drop, store {
        from: address,
        store: Object<FungibleStore>,
        amount: u64,
    }

    #[event]
    struct TransferAdmin has drop, store {
        admin: address,
        pending_admin: address,
    }

    #[event]
    struct AcceptAdmin has drop, store {
        old_admin: address,
        new_admin: address,
    }

    #[view]
    public fun pat_address(): address {
        object::create_object_address(&PATCoin, PAT_SYMBOL)
    }

    #[view]
    public fun metadata(): Object<Metadata> {
        object::address_to_object(pat_address())
    }

    #[view]
    public fun admin(): address acquires ManagedFungibleAsset {
        borrow_global<ManagedFungibleAsset>(pat_address()).admin
    }

    /// Initialize metadata object and store the refs.
    // :!:>initialize
    fun init_module(admin: &signer) {
        let constructor_ref = &object::create_named_object(admin, PAT_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(PAT_NAME),
            utf8(PAT_SYMBOL),
            PAT_DECIMALS,
            string::utf8(ICON_URI),
            string::utf8(PROJECT_URI),
        );


        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let metadata_object_signer = object::generate_signer(constructor_ref);
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset {
            mint_ref: fungible_asset::generate_mint_ref(constructor_ref),
            burn_ref: fungible_asset::generate_burn_ref(constructor_ref),
            transfer_ref: fungible_asset::generate_transfer_ref(constructor_ref),
            admin: @photon_admin,
            pending_admin: @0x0,
            }
        ); // <:!:initialize

        // Create a global state to pause the PAT coin and move to Metadata object.
        move_to(
            &metadata_object_signer,
            State { paused: false, }
        );

        // Override the deposit and withdraw functions which mean overriding transfer.
        // This ensures all transfer will call withdraw and deposit functions in this module
        // and perform the necessary checks.
        // This is OPTIONAL. It is an advanced feature and we don't NEED a global state to pause the PAT coin.
        let deposit = function_info::new_function_info(
            admin,
            string::utf8(b"pat_coin"),
            string::utf8(b"deposit"),
        );
        let withdraw = function_info::new_function_info(
            admin,
            string::utf8(b"pat_coin"),
            string::utf8(b"withdraw"),
        );
        dispatchable_fungible_asset::register_dispatch_functions(
            constructor_ref,
            option::some(withdraw),
            option::some(deposit),
            option::none(),
        );
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&PATCoin, PAT_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }

    /// Deposit function override to ensure that the account is not denylisted and the PAT coin is not paused.
    /// OPTIONAL
    public fun deposit<T: key>(
        store: Object<T>,
        pat: FungibleAsset,
        transfer_ref: &TransferRef,
    ) acquires State {
        assert!(fungible_asset::transfer_ref_metadata(transfer_ref) == metadata(), EINVALID_ASSET);
        assert_not_paused();
        fungible_asset::deposit_with_ref(transfer_ref, store, pat);
    }

    /// Withdraw function override to ensure that the account is not denylisted and the PAT coin is not paused.
    /// OPTIONAL
    public fun withdraw<T: key>(
        store: Object<T>,
        amount: u64,
        transfer_ref: &TransferRef,
    ): FungibleAsset acquires State {
        assert!(fungible_asset::transfer_ref_metadata(transfer_ref) == metadata(), EINVALID_ASSET);
        assert_not_paused();
        fungible_asset::withdraw_with_ref(transfer_ref, store, amount)
    }

    // :!:>mint
    /// Mint as the owner of metadata object.
    public entry fun mint(admin: &signer, to: address, amount: u64) acquires ManagedFungibleAsset {
        assert_is_admin(admin);
        let primary_store = primary_fungible_store::ensure_primary_store_exists(to, get_metadata());
        let managed_fungible_asset = borrow_global<ManagedFungibleAsset>(pat_address());
        let pat = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, primary_store, pat);
        event::emit(Mint { to, amount });

    }

    /// Transfer as the owner of metadata object ignoring `frozen` field.
    public entry fun transfer(admin: &signer, from: address, to: address, amount: u64) acquires ManagedFungibleAsset, State {
        assert_not_paused();
        let transfer_ref = &borrow_global<ManagedFungibleAsset>(pat_address()).transfer_ref;

        let from_wallet = primary_fungible_store::primary_store(from, get_metadata());
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, get_metadata());
        let pat = withdraw(from_wallet, amount, transfer_ref);
        deposit(to_wallet, pat, transfer_ref);
    }

    /// Burn fungible assets as the owner of metadata object.
    public entry fun burn(admin: &signer, from: address, amount: u64) acquires ManagedFungibleAsset {
        assert_is_admin(admin);

        let asset = get_metadata();
        let burn_ref = &borrow_global<ManagedFungibleAsset>(pat_address()).burn_ref;

        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, amount);
    }

    /// Freeze an account so it cannot transfer or receive fungible assets.
    public entry fun freeze_account(admin: &signer, account: address) acquires ManagedFungibleAsset {
        assert_is_admin(admin);
        let asset = get_metadata();
        let transfer_ref = &borrow_global<ManagedFungibleAsset>(pat_address()).transfer_ref;
        let wallet = primary_fungible_store::ensure_primary_store_exists(account, asset);
        fungible_asset::set_frozen_flag(transfer_ref, wallet, true);
    }

    /// Unfreeze an account so it can transfer or receive fungible assets.
    public entry fun unfreeze_account(admin: &signer, account: address) acquires ManagedFungibleAsset {
        assert_is_admin(admin);
        let asset = get_metadata();
        let transfer_ref = &borrow_global<ManagedFungibleAsset>(pat_address()).transfer_ref;
        let wallet = primary_fungible_store::ensure_primary_store_exists(account, asset);
        fungible_asset::set_frozen_flag(transfer_ref, wallet, false);
    }

    /// Pause or unpause the transfer of PAT coin. This checks that the caller is the pauser.
    public entry fun set_pause(pauser: &signer, paused: bool) acquires State,ManagedFungibleAsset {
        assert_is_admin(pauser);
        let asset = get_metadata();
        let state = borrow_global_mut<State>(object::create_object_address(&PATCoin, PAT_SYMBOL));
        if (state.paused == paused) { return };
        state.paused = paused;
    }

    fun assert_is_admin(account: &signer) acquires ManagedFungibleAsset {
        let management = borrow_global<ManagedFungibleAsset>(pat_address());
        assert!(signer::address_of(account) == management.admin, EUNAUTHORIZED);
    }

    /// Assert that the PAT coin is not paused.
    /// OPTIONAL
    fun assert_not_paused() acquires State {
        let state = borrow_global<State>(object::create_object_address(&PATCoin, PAT_SYMBOL));
        assert!(!state.paused, EPAUSED);
    }

}