# Working with fungible tokens wallet and root

## 1. Introduction

You can use the TONOS-CLI utility to deploy contracts and manage them.
Available actions in TONOS-CLI include the following:

* setting the network that the utility should connect to 
* creating seed phrases, private and public keys, which will be used for wallet management
* generating contract address
* deploying contract
* checking contract balance and status
* running getter contract methods
* executing contract methods

## 2. TONOS-CLI Installation
### 2.1. Install TONOS-CLI and download contract files
#### Linux

Create a folder. Download the .tar.gz file from the latest release from here: https://github.com/tonlabs/tonos-cli/releases to this folder. Extract it:

```
tar -xvf tonos-cli_v0.1.1_linux.tar.gz
```
Download token contract files (RootTokenContract.cpp, RootTokenContract.hpp, TONTokenWallet.cpp, TONTokenWallet.hpp) from https://github.com/tonlabs/ton-labs-contracts/tree/master/cpp/tokens-fungible. Place them into the folder containing the TONOS-CLI executable.

> Note: Make sure you have downloaded the raw versions of the files. If you use wget or curl be aware that github can send you a redirection page instead of a file. Use appropriate tool flag to avoid it.

#### Mac OS

Install Cargo: https://github.com/rust-lang/cargo#compiling-from-source

Build TONOS-CLI tool from source:

```
> git clone <https://github.com/tonlabs/tonos-cli.git>

> cd tonos-cli

> cargo build --release

> cd target/release/
```
Download token contract files (RootTokenContract.cpp, RootTokenContract.hpp, TONTokenWallet.cpp, TONTokenWallet.hpp) from https://github.com/tonlabs/ton-labs-contracts/tree/master/cpp/tokens-fungible. Place them into the tonos-cli/target/release/ utility folder.

> Note: Make sure you have downloaded the raw versions of the files. If you use wget or curl be aware that github can send you a redirection page instead of a file. Use appropriate tool flag to avoid it.

> Note: On Mac OS all calls of the TONOS-CLI utility should be performed from the tonos-cli/target/release/ folder.

#### Windows

The workflow is the same as for Mac OS (see the section above). However, when using Windows command line, the following syntax should be used for all TONOS-CLI commands:
```
tonos-cli <command_name> <options>
```
Simply omit the `./` symbols before `tonos-cli`.

### 2.2. Set blockchain network

> Note: By default TONOS-CLI connects to net.ton.dev network.

Use the following command to switch to any other network

```
./tonos-cli config --url <https://network_url>
```

You need to do it only once before using the utility.

A .json configuration file will be created in the TONOS-CLI utility folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

## 3. Installing clang for TVM

Install clang from https://github.com/tonlabs/TON-Compiler.

## 4. Build contracts
```
clang++ RootTokenContract.cpp -o RootTokenContract.tvc
clang++ TONTokenWallet.cpp -o TONTokenWallet.tvc
```
It will generate both tvc and abi files.

## 5. Deploying token root to the Blockchain
### 5.1. Generating seed phrase
To generate your seed phrase enter the following command:
```
./tonos-cli genphrase
```
Terminal displays the generated seed phrase.
> Note: The seed phrase ensures access to the token root. If lost, the custodian will no longer be able to manage the root. The seed phrase should be kept secret and securely backed up.

### 5.2. Generating token root address and deployment key pair
1. Use the following command:
```
./tonos-cli getkeypair <deploy.keys.json> "<seed_phrase>"
```
`deploy.keys.json` - the file the key pair will be written to.
The utility generates the file that contains the key pair produced from seed phrase. Use it to generate your address:
```
./tonos-cli genaddr RootTokenContract.tvc RootTokenContract.abi --setkey deploy.keys.json --wc <workchain_id>
```
* `deploy.keys.json` - the file the key pair is read from.
* `--wc <workchain_id>` - (optional) ID of the workchain the wallet will be deployed to (-1 for masterchain, 0 for basechain). By default this value is set to 0.
The utility displays the new token root address (Raw_address).

> Note: The token root address is required for any interactions with the contract.

#### 5.2.1. (Optional) Check that a contract with the address generated on the previous step does not already exist in the blockchain
Request status for the generated contract address from the blockchain:
```
./tonos-cli account <root_address>
```
#### 5.2.2. Send a few tokens to the new address from another contract.
Create, and if necessary, confirm a transaction from another wallet. 
Ensure that contract address has been created in the blockchain and has Uninit status.
```
./tonos-cli account <root_address>
```
### 5.3. Place token wallet code into variable
TONTokenWallet code must be provided into RootTokenContract constructor, so we need to save TONTokenWallet.tvc code into variable:
```
tvm_linker decode --tvc TONTokenWallet.tvc > code.txt
```
> Note: tvm_linker utility: https://github.com/tonlabs/TVM-linker

Edit code.txt to keep only `code: ` section content.
Save code.txt content into variable:
```
export TVM_WALLET_CODE=`cat code.txt`
```

### 5.4. Deploy the root contract to the blockchain
Use the following command:
> Note: "name":"54657374","symbol":"545354" means token name "Test" and symbol "TST".
> Note: you can use `echo -n "TST" | xxd -p` for "name"/"symbol" values generation from string.
```
./tonos-cli deploy RootTokenContract.tvc '{"name":"54657374","symbol":"545354", "decimals":"0","root_public_key":"0x<Root public key>", "root_owner":"0", "wallet_code":"'$TVM_WALLET_CODE'","total_supply":"<Number of tokens>"}' --abi RootTokenContract.abi --sign deploy.keys.json --wc <workchain_id>
```
Configuration parameters:
* `name` - name of the token.
* `symbol` - short symbol of the token.
* `decimals` - the number of decimals the token uses; e.g. 8, means to divide the token amount by 100,000,000 to get its user representation.
* `root_public_key` - public key from deploy.keys.json. Make sure public key is enclosed in quotes and start with `0x...`.
* `wallet_code` - base64-encoded token wallet code.
* `total_supply` - total number of initial tokens minted.
* `--wc <workchain_id>` - (optional) ID of the workchain the wallet will be deployed to (-1 for masterchain, 0 for basechain). By default this value is set to 0.

#### 5.4.1. Check the token root status again
Now it should be Active.
```
./tonos-cli account <root_address>
```

#### 5.4.2. Run getters of the token root contract
Verify that state matches parameters you have provided during deploy.
```
./tonos-cli run <root_address> getName {} --abi RootTokenContract.abi
./tonos-cli run <root_address> getSymbol {} --abi RootTokenContract.abi
./tonos-cli run <root_address> getDecimals {} --abi RootTokenContract.abi
./tonos-cli run <root_address> getRootKey {} --abi RootTokenContract.abi
./tonos-cli run <root_address> getTotalSupply {} --abi RootTokenContract.abi
./tonos-cli run <root_address> getWalletCode {} --abi RootTokenContract.abi
```

`getTotalGranted` must be zero for just created token root:
```
./tonos-cli run <root_address> getTotalGranted {} --abi RootTokenContract.abi
```

## 6. Token Root management
### 6.1. Selecting blockchain network

> Note: By default TONOS-CLI connects to net.ton.dev network.

Use the following command to switch to any other network 
```
./tonos-cli config --url <https://network_url>
```
You need to do it only once before using the utility.

A .json configuration file will be created in the TONOS-CLI utility folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

### 6.2. Calculating token wallet address for specified wallet public key
```
./tonos-cli run <root_address> getWalletAddress '{"workchain_id":<workchain_id>,"pubkey":"0x<wallet public key>", "owner_std_addr":"0"}' --abi RootTokenContract.abi
```

### 6.3. Deploying token wallet from token root
```
./tonos-cli call <root_address> deployWallet '{"_answer_id":"0", "workchain_id":<workchain_id>,"pubkey":"0x<wallet public key>", "internal_owner":"0", "tokens":"<Tokens number>","grams":<Tons>}' --sign deploy.keys.json --abi RootTokenContract.abi
```
The call will return the deployed wallet address. It should be equal to calculated by getWalletAddress.

### 6.4. Minting new tokens
```
./tonos-cli call <root_address> mint '{"tokens":"<Tokens number>"}' --sign "<seed_phrase>"
```

### 6.5. Granting tokens to existing token wallet
```
./tonos-cli call <root_address> grant '{"dest":"<token wallet address>","tokens":"<Tokens number>","tons":"<Tons>"}' --sign "<seed_phrase>"
```

## 7. Token Wallet management
### 7.1. Token Wallet state
```
./tonos-cli run <wallet_address> getName {} --abi TONTokenWallet.abi
./tonos-cli run <wallet_address> getSymbol {} --abi TONTokenWallet.abi
./tonos-cli run <wallet_address> getDecimals {} --abi TONTokenWallet.abi
./tonos-cli run <wallet_address> getBalance {} --abi TONTokenWallet.abi
./tonos-cli run <wallet_address> getWalletKey {} --abi TONTokenWallet.abi
./tonos-cli run <wallet_address> getRootAddress {} --abi TONTokenWallet.abi
./tonos-cli run <wallet_address> allowance {} --abi TONTokenWallet.abi
```

### 7.2. Transfer tokens
```
./tonos-cli call <wallet_address> transfer '{"dest":"<dest token wallet address>","tokens":<Tokens number>,"tons":<Tons>}' --sign "<seed_phrase>"
```

### 7.3. Set allowance
```
./tonos-cli call <wallet_address> approve '{"spender":"<spender token wallet address>","remainingTokens":0,"tokens":<Tokens number>}' --sign "<seed_phrase>"
```

### 7.4. Unset allowance
```
./tonos-cli call <wallet_address> disapprove {} --sign "<seed_phrase>"
```

