module PhotonResourceAddress::PhotonAdmin {
    use std::signer;
    use std::vector;
    use std::client_registry;
    use std::user_registry;
    use std::user_registry;
    use PhotonResourceAddress::client_registry::{Self, ClientRegistry};
    use PhotonResourceAddress::user_registry::{Self, UserRegistry};
    use PhotonResourceAddress::merchant_registry::{Self, MerchantStoreManager};

    const DEV: address = @PhotonDevAddress;
    const ZERO_ACCOUNT: address = @zero;
    const DEFAULT_ADMIN: address = @default_admin;
    const RESOURCE_ACCOUNT: address = @PhotonResourceAddress;


    const ADMIN_NOT_FOUND: u64 = 1;
    const TOKEN_DECIMALS: u64 = 100000000;


    struct AdminInfo has key, store {
        signer_cap: account::SignerCapability,
        admin_address: address,
        created_at: u64,
        coin_type: address,
        clientStore: ClientRegistry,
        userStore: UserRegistry,
        totalSpend: u128,
        campaignStore: MerchantStoreManager,
        whitelisted_processors: vector<address>,
        platform_spend_fee_percent: u8,
        platform_earn_fee_percent: u8
    }

    /// Initialize the Admin resource on the deployer/admin account.
    public entry fun initialize(admin_signer: &signer) {
        let addr = signer::address_of(admin_signer);
        assert!(!exists<Admin>(addr), 0);
        move_to(admin_signer, Admin {
            admin_address: addr,
            admin_wallet_balance: u128,
            created_at: timestamp::now_seconds(),
        });
    }

    fun init_module(sender: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEV);
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        assert!(!exists<AdminInfo>(addr), ADMIN_NOT_FOUND);

        move_to(&resource_signer, AdminInfo {
            signer_cap: signer_cap,
            admin: DEFAULT_ADMIN,
            created_at: timestamp::now_seconds(),
            coin_type: ZERO_ACCOUNT, // placeholder for coin type address
            clientStore: ClientStore {
                owner: ZERO_ACCOUNT,
                clientMap: SimpleMap::empty(),
                isProtocol: SimpleMap::empty(),
            },
            userStore: UserRegistry {
                owner: ZERO_ACCOUNT,
                users: vector::empty(),
                created_at: timestamp::now_seconds(),
            },
            totalSpend: 0, // total spend in numeric tokens
            campaignStore: MerchantStoreManager {
                owner: ZERO_ACCOUNT,
                merchant_accounts: vector::empty(),
                wallet_balance: 0,
                coin_type_address: ZERO_ACCOUNT,
                created_at: timestamp::now_seconds(),
            },
            whitelisted_processors: vector::empty(),
            platform_spend_fee_percent: 0, // default 0%
            platform_earn_fee_percent: 0, // default 0%
        });
    }

}
