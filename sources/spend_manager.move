module photon_spend_manager::PhotonSpendManagerModule {
    use std::signer;
    use photon_user_module_deployer::PhotonUsersModule::{Self, is_registered};
    use photon_merchant_deployer::PhotonMerchantManagerModule::{Self, credit_merchant_wallet};

    const E_INVALID_AMOUNT: u64 = 1;

    public entry fun make_payment_to_merchant(
        user: &signer,
        amount: u128,
    ) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let user_address = signer::address_of(user);

        is_registered(user_address);
        credit_merchant_wallet(user,1,amount);
    }
}
