module photon_admin::PhotonSpendManagerModule {
    use std::signer;
    use photon_admin::PhotonUserModule;
    use photon_admin::PhotonMerchantManagerModule;

    const E_INVALID_AMOUNT: u64 = 1;

    /// Make payment from user internal numeric balance to merchant manager wallet.
    /// This debits the user's balance and credits the specified merchant via their manager.
    public entry fun make_payment_to_merchant(
        admin: &signer,
        user_addr: address,
        merchant_id: vector<u8>,
        amount: u128,
    ) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        PhotonUserModule::debit_tokens(admin, user_addr, amount);
        PhotonMerchantManagerModule::credit_merchant_wallet(admin, merchant_address, amount);
    }

    /// Claim tokens to the user wallet (e.g., payouts/rewards)
    public entry fun claim_to_user_wallet(
        admin: &signer,
        user_addr: address,
        amount: u128,
    ) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        PhotonUserModule::credit_tokens(admin, user_addr, amount);
    }
}
