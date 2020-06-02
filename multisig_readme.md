# Multisignature Wallet Management in TONOS-CLI

## 1. Introduction

Multisignature wallet is a crypto wallet on the blockchain, which supports multiple owners (custodians), who are authorized to manage the wallet.

You can use the [TONOS-CLI](https://github.com/tonlabs/tonos-cli) utility to deploy multisignature wallets and manage them.

Available actions in TONOS-CLI include the following:

* Configure TONOS-CLI environment
* Create seed phrase, private/public keys
* Create wallet
* Check wallet balance
* List transactions awaiting confirmation
* Create transactions
* Confirm transactions

### Glossary

`Multisignature wallet` - crypto wallet on the blockchain, which supports multiple owners (custodians), who are authorized to manage the wallet.

`Wallet address` - unique address of the wallet on the blockchain. It explicitly identifies the wallet and is required for any actions with the wallet to be performed. It does not, on its own, provide anyone access to wallet funds.

`Wallet custodian` - authorized owner of the wallet. Owns the private key and corresponding seed phrase, which are required to make any changes to the wallet or wallet funds. Wallet may have more than one custodian.

`Custodian private key` - the unique cryptographic key belonging to the wallet custodian, which authorizes access to the wallet. Should be kept secret.

`Custodian seed phrase` - unique mnemonic phrase exactly corresponding to the custodian private key. Can be used to restore the private key, or to sign transactions in TONOS-CLI instead of it. Should be kept secret and securely backed up.

`Custodian public key` - public key forming a cryptographic key pair with the custodian private key. It is not secret and may be freely shared with anyone.

`Validator` - the entity performing validation of new blocks on the blockchain through a Proof-of-Stake system. Requires a multisignature wallet for staking.

## 2. Install TONOS-CLI
### 2.1. Install TONOS-CLI utility
#### Compiled utility installation on Linux

Create a folder. Download the `.tar.gz` file from the latest release from here: https://github.com/tonlabs/tonos-cli/releases to this folder. Extract it:
```
tar -xvf ./tonos-cli_v0.1.3_linux.tar.gz
```
#### Build from source on Linux and Mac OS

Install Cargo: https://github.com/rust-lang/cargo#compiling-from-source

Build TONOS-CLI tool from source:
```
git clone https://github.com/tonlabs/tonos-cli.git
cd tonos-cli
cargo update
cargo build --release
cd target/release
```
The `tonos-cli` executable is built in the `tonos-cli/target/release` folder. Create a folder elsewhere. Copy the `tonos-cli` executable into the new folder you have created.

#### Build from source on Windows

Install Cargo: https://github.com/rust-lang/cargo#compiling-from-source

Build TONOS-CLI tool from source:
```
> git clone https://github.com/tonlabs/tonos-cli.git
> cd tonos-cli
> cargo update
> cargo build --release
> cd target/release
```

The `tonos-cli` executable is built in the `tonos-cli/target/release` folder. Create a folder elsewhere. Copy the `tonos-cli` executable into the new folder you have created.

##### A note on Windows syntax

When using Windows command line, the following syntax should be used for all TONOS-CLI commands:

1. Never use the `./` symbols before `tonos-cli`:
```
> tonos-cli <command_name> <options>
```
2. For all commands with nested quotes, the outer single quotes should be changed to double quotes, and the inner double quotes should be shielded by a preceding `\`. 
Example:
```
> tonos-cli deploy SafeMultisigWallet.tvc "{\"owners\":[\"0x723b2f0fa217cd10fe21326634e66106678f15d5a584babe4f576dffe9dcbb1b\",\"0x127e3ca223ad429ddaa053a39fecd21131df173bb459a4438592493245b695a3\",\"0xc2dd3682ffa9df97a968bef90b63da90fc92b22163f558b63cb7e52bfcd51bbb\"],\"reqConfirms\":2}" --abi SafeMultisigWallet.abi.json --sign deploy.keys.json
```

#### Tails OS secure environment

For maximum security while managing your wallet, you can use the Tails OS for all actions that can be performed offline. Follow all steps of the [Creating secure environment with Tails OS and TONOS-CLI](https://docs.ton.dev/86757ecb2/v/0/p/906c40-creating-secure-environment-with-tails-os-and-tonos-cli) document to install TONOS-CLI.

You can perform the following actions entirely offline:

* Generate seed phrases and custodian keys
* Prepare new transaction  offline
* Prepare transaction confirmation offline


### 2.2. Download contract files 

Download compiled `.abi.json` and `.tvc` multisignature contract files from https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity

Choose a contract version:

* **SafeMultisig** - basic multisignature wallet, does not permit contract code modification. Is required if you use validator scripts.

`SafeMultisigWallet.abi.json` direct link:

https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/master/solidity/safemultisig/SafeMultisigWallet.abi.json

 `SafeMultisigWallet.tvc` direct link:

https://github.com/tonlabs/ton-labs-contracts/raw/master/solidity/safemultisig/SafeMultisigWallet.tvc

* **SetcodeMultisig** - more advanced multisignature wallet. This version is currently required to create a wallet that can be managed TON Surf:

`SetcodeMultisigWallet.abi.json` direct link:

https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/master/solidity/setcodemultisig/SetcodeMultisigWallet.abi.json

`SetcodeMultisigWallet.tvc` direct link:

https://github.com/tonlabs/ton-labs-contracts/raw/master/solidity/setcodemultisig/SetcodeMultisigWallet.tvc

Place both files into the folder containing the `tonos-cli` executable.

> **Note**: Make sure you have downloaded the **raw** versions of the files. A common error when downloading from the github project page manually is to save the redirection page instead of the raw file.


### 2.3. Configure TONOS-CLI environment

1. (Optional, Linux/Mac OS) Put `tonos-cli` into system environment:
```
export PATH="<tonos_folder_path>:$PATH"
```
If you skip this step, make sure you run the utility from the utility folder: 
```
./tonos-cli <command> <options>
```

2. Use the following command to set the network:
```
tonos-cli config --url <https://network_url>
```
> **Note**:  Make sure to specify URL in the following format: `https://net.ton.dev` (without a slash at the end).

There are two networks currently available:

`https://net.ton.dev` - developer sandbox for testing.

`https://main.ton.dev` - main Free TON network, currently in beta.

You need to do it only once before using the utility.

`tonlabs-cli.conf.json` configuration file will be created in the utility folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

> **Note**: By default `tonos-cli` connects to `net.ton.dev` network.

> **Note**: Always run `tonos-cli` utility only from the folder where `tonlabs-cli.conf.json` is placed.


## 3. Create Wallet

The following actions should be performed to create a wallet:

1. Create wallet seed phrase
2. Generate deployment key pair file with wallet private/public keys based on the wallet seed phrase
3. Generate wallet address based on the wallet seed phrase
4. Send some tokens to the wallet address
5. Deploy wallet (set custodians)

All of these steps are detailed in this section.

### 3.1. Create seed phrases and public keys for all custodians
#### 3.1.1. Create wallet seed phrase

To generate your seed phrase enter the following command:
```
tonos-cli genphrase
```
Terminal displays the generated seed phrase.

> **Note**: Seed phrases should be created for every custodian of the multisignature wallet.

> The seed phrase ensures access to the multisignature wallet. If lost, the custodian will no longer be able to manage the wallet. The seed phrase is unique for every custodian and should be kept secret and securely backed up (word order matters).

#### 3.1.2. Generate public key

To generate your public key enter the following command with your previously generated seed phrase in quotes:
```
tonos-cli genpubkey "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```
Copy the generated code from Terminal or scan the QR code containing the code with your phone and send it to whichever custodian is responsible for deploying the multisignature wallet.

> **Note**: The public key should also be generated for every custodian. The public key is not secret and can be freely transmitted to anyone.

### 3.2. Generate deployment key pair file

Any custodian who has received the public keys of all other custodians can deploy the multisignature wallet to the blockchain.

To create the key pair file from the seed phrase generated at step **3.1.1** use the following command:
```
tonos-cli getkeypair <deploy.keys.json> "<seed_phrase>"
```
`<deploy.keys.json>` - the file the key pair will be written to.

The utility generates the file that contains the key pair produced from seed phrase.

### 3.3. Generate wallet address

Use deployment key pair file to generate your address:
```
tonos-cli genaddr <MultisigWallet.tvc> <MultisigWallet.abi.json> --setkey <deploy.keys.json> --wc <workchain_id>
```
`<MultisigWallet.tvc>` - either `SafeMultisigWallet.tvc` or `SetcodeMultisigWallet.tvc` depending on the contract you have selected at step **2.2**.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

`<deploy.keys.json>` - the file the key pair is read from.

`--wc <workchain_id>` - (optional) ID of the workchain the wallet will be deployed to (`-1` for masterchain, `0` for basechain). By default this value is set to `0`.

> **Note**: Masterchain fees are significantly higher, but masterchain is required for validator wallets. Make sure to set workchain ID to `-1` for any validator wallets you are deploying: `--wc -1`. Basechain, on the other hand, is best suited for user wallets.

The utility displays the new multisignature wallet address (Raw_address).

> **Note**: The wallet address is required for any interactions with the wallet. It should be shared with all wallet custodians.


### 3.4. Send tokens to the new address from another wallet

Use the following command to create a new transaction from another existing wallet:
```
tonos-cli call <source_address> submitTransaction '{"dest":"<raw_address>","value":<nanotokens>,"bounce":false,"allBalance":false,"payload":""}' --abi <MultisigWallet.abi.json> --sign "<source_seed>"
```
`<source_address>` - address of the wallet the funds are sent from.

`<source_seed>` - seed phrase for the wallet the funds are sent from.

`"dest":<raw_address>` - new wallet address generated at step **3.3**. Example: `"0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3"`

`"value"`: - amount of tokens to transfer in nanotokens (Example: `"value":10000000000` sets up a transfer of 10 tokens).

`"bounce"` - use `false` to transfer funds to a non-existing contract to create it.

`"allBalance"` - use `true` (and value = 0) if you need to transfer all contract funds. Don't use value equal to contract balance to send all remaining tokens, such transaction will fail because before the value is subtracted from balance, gas and storage fees are consumed and the remaining balance will be less than `value`.

`"payload"` - use `""` for simple transfer.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

If the wallet has multiple custodians, the transaction requires confirmation from the other custodians.


To confirm the transaction use the following command:
```
tonos-cli call <source_address> confirmTransaction '{"transactionId":"<id>"}' --abi <MultisigWallet.abi.json> --sign "<source_seed>"
```
`<source_address>` - address of the wallet to funds are sent from.

`<source_seed>` - seed phrase for the wallet the funds are sent from.

`transactionId` – the ID of the transaction transferring tokens to the new  wallet.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

Ensure that the new wallet has been created in the blockchain and has **Uninit** status:
```
tonos-cli account <multisig_address>
```
`<multisig_address>` - new wallet address generated at step **3.3**.

### 3.5. Deploy wallet (set custodians)
#### 3.5.1. Deploy the wallet to blockchain

Use the following command:
```
tonos-cli deploy <MultisigWallet.tvc> '{"owners":["0x...", ...],"reqConfirms":N}' --abi <MultisigWallet.abi.json> --sign <deploy_seed_or_keyfile> --wc <workchain_id>
```
Configuration parameters:

`<MultisigWallet.tvc>` - either `SafeMultisigWallet.tvc` or `SetcodeMultisigWallet.tvc` depending on the contract you have selected at step **2.2**.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

`owners` - array of custodian public keys generated by all wallet custodians at step **3.1.2** as uint256 numbers. Make sure all public keys are enclosed in quotes and start with `0x....` 

Example: `"owners":["0x8868adbf012ebc349ced852fdcf5b9d55d1873a68250fae1be609286ddb962582", "0xa0e16ccff0c7bf4f29422b33ec1c9187200e9bd949bb2dd4c7841f5009d50778a"]`

`reqConfirms` - number of signatures needed to confirm a transaction ( 0 < `N` ≤ custodian count).

`--wc <workchain_id>` - (optional) ID of the workchain the wallet will be deployed to (`-1` for masterchain, `0` for basechain). By default this value is set to `0`.

> **Note**: Masterchain fees are significantly higher, but masterchain is required for validator wallets. Make sure to set workchain ID to `-1` for any validator wallets you are deploying: `--wc -1`. Basechain, on the other hand, is best suited for user wallets.

`<deploy_seed_or_keyfile>` - can either be the seed phrase used in step **3.2** to generate the deployment key pair file or the `deploy.keys.json` file itself. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign deploy.keys.json`

Deploying a wallet without at least one custodian is not possible, since every transaction from a wallet has to be signed by one or more custodians (depending on wallet configuration) with their private key or equivalent seed phrase. It is a basic security requirement of the system.

> **Note**: After a wallet is deployed, for reasons of security you cannot add or remove custodians from it. If you want to change the custodian list, you have to create a new wallet, transfer all funds there, and set the new list of custodians.

#### 3.5.2. Check that the wallet is active

Check the new wallet status again. Now it should be Active.
```
tonos-cli account <multisig_address>
```

#### 3.5.3. Request the list of custodian public keys from the blockchain

Verify that they match the keys you have loaded during deploy.
```
tonos-cli run <multisig_address> getCustodians {} --abi SafeMultisigWallet.abi.json
```
The wallet is deployed and the owners of the listed public keys have access to it.

## 4. Manage Wallet
### 4.1. Select blockchain network

There are two networks currently available:

`https://net.ton.dev` - developer sandbox for testing.

`https://main.ton.dev` - main Free TON network, currently in beta.

Use the following command to switch to any of these networks:
```
tonos-cli config --url <https://network_url>
```
> **Note**: Make sure to specify URL in the following format: `https://net.ton.dev` (without a slash at the end).

You need to do it only once before using the utility.

A `.json` configuration file will be created in the TONOS-CLI utility folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

###  4.2. Convert tokens to nanotokens

Amounts in multisignature transactions are indicated in nanotokens. To convert tokens to nanotokens use the following command:
```
tonos-cli convert tokens <amount>
```

### 4.3. Check wallet balance and status
#### 4.3.1. Check wallet balance and status with TONOS-CLI

You may use the following command to check the current status and balance of your wallet:
```
tonos-cli account <multisig_address>
```
It displays the wallet status:

* `Not found` – if the wallet does not exist
* `Uninit` – wallet was created, but contract code wasn’t deployed
* `Active` – wallet exists and has the contract code and data

It also displays the wallet balance, time of the most recent transaction and contract data block.

#### 4.3.2. Check wallet balance and status in the blockchain explorer

The detailed status of the account can also be viewed in the [ton.live](https://ton.live/main) blockchain explorer.

Select the network the wallet is deployed to and enter the **raw address** of the wallet into the main search field.

Account status, balance, message and transaction history for the account will be displayed.

### 4.4. List custodian public keys

The following command displays the list of public keys, the owners of which have rights to manage the wallet:
```
tonos-cli run <multisig_address> getCustodians {} --abi <MultisigWallet.abi.json>
```

### 4.5. List transactions awaiting confirmation

Use the following command to list the transactions currently awaiting custodian confirmation:
```
tonos-cli run <multisig_address> getTransactions {} --abi <MultisigWallet.abi.json>
```
If there are some transactions requiring confirmation, they will be displayed.

### 4.6. Create transaction online

Use the following command to create a new transaction:
```
tonos-cli call <multisig_address> submitTransaction '{"dest":"raw_address","value":<nanotokens>,"bounce":true,"allBalance":false,"payload":""}' --abi <MultisigWallet.abi.json> --sign <seed__or_keyfile>
```
`"dest"` - raw address of a destination smart contract. Example: `"0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3"`

`"value":` - amount of tokens to transfer in nanotokens (Example: `"value":10000000000` sets up a transfer of 10 tokens).

`"bounce"` - use `false` to transfer funds to a non-existing contract to create it. Use `true` to transfer funds to an Active contract.

> **Note**: at step **3.4** of the wallet deployment procedure use `false`.

`"allBalance"` - use `true` (and value = 0) if you need to transfer all contract funds. Don't use value equal to contract balance to send all remaining tokens, such transaction will fail because before the value is subtracted from balance, gas and storage fees are consumed and the remaining balance will be less than `value`.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

`"payload"` - use `""` for simple transfer. Otherwise payload is used as a body of outbound internal message.

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign keyfile.json`

If the wallet has multiple custodians and more than one custodian signature is required to execute a transaction, the new transaction is queued in the wallet and waits for the necessary amount of confirmations. Otherwise it is executed immediately.

> **Note**: For maximum security you may also create a transaction message on a machine without internet connection in offline mode. See section **4.8**.

### 4.7. Create transaction confirmation online

Once one of the custodians creates a new transaction on the blockchain, it has to get the required number of confirmations from other custodians.

To confirm a transaction, use the following command:
```
tonos-cli call <multisig_address> confirmTransaction '{"transactionId":"<id>"}' --abi <MultisigWallet.abi.json> --sign <seed_or_keyfile>
```
`transactionId` – the ID of the transaction can be acquired from the custodian who created it, or by requesting the list of transactions awaiting confirmation from the multisignature wallet.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign keyfile.json`

> **Note**: If the wallet has only one custodian, or if the number of confirmations required to perform a transaction was set to 1, this action won't be necessary. The transaction will be confirmed automatically.

> **Note**: For maximum security you may also create a transaction confirmation message on a machine without internet connection in offline mode. See section **4.9**.


### 4.8. Create new transaction offline

An internet connection is not required to create a signed transaction message. Use the following command to do it:
```
tonos-cli message <multisig_address> submitTransaction '{"dest":"raw_address","value":<nanotokens>,"bounce":true,"allBalance":false,"payload":""}' --abi <MultisigWallet.abi.json> --sign <seed_or_keyfile> --lifetime 3600
```
`"dest"` - raw address of a destination smart contract. Example: `"0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3"`.

`"value":` - amount of tokens to transfer in nanotokens (Example: `"value":10000000000` sets up a transfer of 10 tokens).

`"bounce"` - use `false` to transfer funds to a non-existing contract to create it. Use `true` to transfer funds to an Active contract.

`"allBalance"` - use `true` (and value = 0) if you need to transfer all contract funds. Don't use value equal to contract balance to send all remaining tokens, such transaction will fail because before the value is subtracted from balance, gas and storage fees are consumed and the remaining balance will be less than `value`.

`"payload"` - use `""` for simple transfer. Otherwise payload is used as a body of outbound internal message.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign keyfile.json`

`lifetime` – message lifetime in seconds. Once this time elapses, the message will not be accepted by the contract.

The TONOS-CLI utility displays encrypted message text and a QR code that contains the submitTransaction message.

Copy the message text or scan the QR code and broadcast the message online. See section **4.10**.

### 4.9. Create transaction confirmation offline

Once one of the custodians creates a new transaction on the blockchain, it has to get the required number of confirmations from other custodians.

To create a confirmation message offline use the following command:
```
tonos-cli message <multisig_address> confirmTransaction '{"transactionId":"<id>"}' --abi <MultisigWallet.abi.json> --sign "<seed_phrase>" --lifetime 600
```
`transactionId` – the ID of the transaction can be acquired from the custodian who created it, or by requesting the list of transactions awaiting confirmation from the multisignature wallet.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign keyfile.json`

`lifetime` – message lifetime in seconds. Once this time elapses, the message will not be accepted by the contract.

The TONOS-CLI utility displays encrypted transaction text and a QR code that contains the `confirmTransaction` message.

Copy the message text or scan the QR code and broadcast the message online. See section **4.10**.

### 4.10. Broadcast previously generated message

Use the following command to broadcast any previously generated message (transaction message or confirmation message):
```
tonos-cli send --abi <MultisigWallet.abi.json> "message"
```
`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step **2.2**.

`message` – the content of the message generated by the TONOS-CLI utility during message creation. It should be enclosed in double quotes.

The terminal displays the result of new transaction creation:
```
Result: {
"transId": "0x5ea98b30fb3f0041"
}
```
To receive confirmations from the required number of fellow wallet custodians, send them this transaction ID.
