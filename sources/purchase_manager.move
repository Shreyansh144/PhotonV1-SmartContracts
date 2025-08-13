module photon_purchase_manager::PhotonPurchaseManagerModule {
    use std::signer;
    use photon_user_module_deployer::PhotonUsersModule::{ Self, debit_tokens};;
    use photon_merchant_deployer::PhotonMerchantManagerModule::{Self, credit_merchant_wallet};;
    use pat_token_deployer::pat_coin::{ Self, get_metadata,transfer,balance};

    const E_INVALID_AMOUNT: u64 = 1;

    public entry fun make_payment_to_merchant(
        user: &signer,
        amount: u128,
    ) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        debit_tokens(user,amount);
        credit_merchant_wallet(user,amount);
    }
}
