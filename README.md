### 📦 1. Initialize Aptos CLI
aptos init


### 🔧 2. Compile the Move Module
aptos move compile --named-addresses my_first_module=default

> Replace `default` with your Aptos account address (e.g., `0xabc...`) if needed.

### 🧪 3. Run Unit Tests
aptos move test --named-addresses my_first_module=default


### 🚀 4. Publish to Blockchain
aptos move publish --named-addresses my_first_module=default

### ▶️ 5. Execute a Function
aptos move run --function-id 'default::message::set_message' --args 'string:Hello, Aptos!'

### 📌 Notes
[addresses]
my_first_module = "default"

* Update `"default"` to your actual address (e.g., `"0x123..."`) once deployed.

---

<!-- module: module FACoin::fa_coin {
 toml file: [package]
name = "fa_coin"
[addresses]
FACoin = "0x123"
-->

# Resource Account Creation:
aptos account create-resource-account --seed b123

# Transfer to Resource Account:
aptos account transfer --account 0xadc --amount 50000

# Derive Resource Account address :
aptos account derive-resource-account-address --address 0xf00 --seed b123  

aptos account list 

aptos account balance --account 

aptos account fund-with-faucet

# current Address:
aptos account lookup-address

# publish resource account on resource account from resource account address & make sure u should have balance in resource account:
aptos move publish --sender-account 0x8f11

# create and publish resource account, module will be publish in the resource account:
aptos move create-resource-account-and-publish-package --address-name 0xf005 --seed test1232

# Case-1: created resource account from SM contains seed like- b"01", but in blockchain it arg shows- 0x01, seed-encoding should looks like --seed-encoding hex --seed 02:
aptos account derive-resource-account-address --address 0xf0051de271b991845c315a842de140b04cfbcee036cc1f1a2f6c6925a9f566c1 --seed-encoding hex --seed 02

{
  "Result": "f68c1bf3d095bb7f86598390a69f5382e9468936666d737039fdc110e0e04658"
}

# Case-2: aptos move create-resource-account-and-publish-package --address-name 0x225743b46742c2fd97dc84c2649a215263831a4665997eee989bf35c3cc3c4f2 --seed 123 after this: 
aptos account derive-resource-account-address --address 0x225743b46742c2fd97dc84c2649a215263831a4665997eee989bf35c3cc3c4f2 --seed-encoding bcs --seed 123

{
  "Result": "d027c18765c05796fec5bb1c652e0465e82bd9d52e45bd80f36a7e8685b68471"
}


# Basic Commands

aptos init

aptos move compile --named-addresses my_first_module=default

aptos move test --named-addresses my_first_module=default

aptos move publish --named-addresses my_first_module=default

aptos move run --function-id 'default::message::set_message' --args 'string:Hello, Aptos!'



# How to manage Move.toml file, below mention all the working ways
[dependencies]

# Step 1:
AptosFramework = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/aptos-framework", rev = "mainnet" }

# Step 2:
AptosFramework = { git = "https://github.com/aptos-labs/aptos-framework.git", subdir = "aptos-framework", rev = "mainnet" }

# Step 3:
AptosFramework = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/aptos-framework/",  rev = "mainnet" }
AptosStdlib = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/aptos-stdlib/",  rev = "mainnet" }

# Step 4:
[dependencies.AptosFramework]
local = './aptos-core/aptos-move/framework/aptos-framework/'

[dependencies.AptosStdlib]
local = './aptos-core/aptos-move/framework/aptos-stdlib/'

# Step 5:
[dependencies.AptosFramework]
local = './aptos-framework/aptos-framework'

[dependencies.AptosStdlib]
local = './aptos-framework/aptos-stdlib/'


# Gas Fee:

1. From publishing module to the resource account: [446600 - 600000] Octas at a gas unit price of 100 Octas

2. Transfer funds to resource account: [55100 - 82600] Octas at a gas unit price of 100 Octas

3. Resource account creation: [51200 - 76800] Octas at a gas unit price of 100 Octas

4. Fa_coin creation contract: [345500 - 518200] Octas at a gas unit price of 100 Octas

5. create-resource-account-and-publish-package: [399400 - 599100] Octas at a gas unit price of 100 Octas


# Upgradeable smart contracts:

[package]
name = "MyApp"
version = "0.0.1"
upgrade_policy = "compatible"
...