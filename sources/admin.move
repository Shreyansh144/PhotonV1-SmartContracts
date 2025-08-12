module photon_admin_deployer::PhotonAdmin {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::resource_account;

    const DEV: address = @photon_dev;
    const ZERO_ACCOUNT: address = @zero;
    const PHOTON_ADMIN: address = @photon_admin;

    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_INVALID_PERCENT: u64 = 1;
    const ERROR_INVALID_ADDRESS: u64 = 2;

    struct Capabilities has key {
        admin: address,
        whitelisted_processors: vector<address>,
        params: SetPlatformFeeParams,
    }

    struct SetPlatformFeeParams has copy, store {
        platform_spend_fee_percent: u8,
        platform_earn_fee_percent: u8
    }

    public entry fun init_admin(sender: &signer) {
        // let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEV);
        let whitelisted_processors = vector[@processors1, @processors2, @processors3];
        let params = SetPlatformFeeParams {
            platform_spend_fee_percent: 0,
            platform_earn_fee_percent: 0
        };

        move_to(sender, Capabilities {
            // signer_cap,
            admin: PHOTON_ADMIN,
            whitelisted_processors,
            params: params
        });
    }

    public entry fun add_whitelisted_processor(admin: &signer, new_processor: address) acquires Capabilities {
        let capabilities = borrow_global_mut<Capabilities>(PHOTON_ADMIN);

        assert!(signer::address_of(admin) == capabilities.admin, ERROR_NOT_ADMIN);
        assert!(new_processor != ZERO_ACCOUNT, ERROR_INVALID_ADDRESS);

        if (vector::contains(&capabilities.whitelisted_processors, &new_processor)) {
            return;
        };
        vector::push_back(&mut capabilities.whitelisted_processors, new_processor);
    }

    public entry fun change_fee_params(
        admin: &signer,
        platform_spend_fee_percent: u8,
        platform_earn_fee_percent: u8
    ) acquires Capabilities {
        let capabilities = borrow_global_mut<Capabilities>(PHOTON_ADMIN);

        assert!(signer::address_of(admin) == capabilities.admin, ERROR_NOT_ADMIN);
        assert!(platform_spend_fee_percent <= 100 && platform_earn_fee_percent <= 100, ERROR_INVALID_PERCENT);

        capabilities.params.platform_spend_fee_percent = platform_spend_fee_percent;
        capabilities.params.platform_earn_fee_percent = platform_earn_fee_percent;
    }

}
