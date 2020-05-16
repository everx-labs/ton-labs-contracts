# Working with Multisignature Wallet

## 1. Introduction

You can use the TONOS-CLI utility to deploy multisignature wallets and manage them.
Available actions in TONOS-CLI include the following:

* setting the network that the utility should connect to 
* creating seed phrases, private and public keys, which will be used for wallet management
* generating wallet address
* deploying wallet
* checking wallet balance and status
* creating transactions
* listing transactions awaiting confirmation
* creating transaction confirmations
* creating offline messages to be broadcasted later


## 2. TONOS-CLI Installation
### 2.1. Install TONOS-CLI and download contract files
#### Linux

Create a folder. Download the .tar.gz file from the latest release from here: https://github.com/tonlabs/tonos-cli/releases to this folder. Extract it:

```
tar -xvf tonos-cli_v0.1.1_linux.tar.gz
```
Download compiled multisignature contract files (SafeMultisigWallet.abi.json and SafeMultisigWallet.tvc) from https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/safemultisig. Place them into the folder containing the TONOS-CLI executable.

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
Download compiled multisignature contract files (SafeMultisigWallet.abi.json and SafeMultisigWallet.tvc) from https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/safemultisig. Place them into the tonos-cli/target/release/ utility folder.

> Note: Make sure you have downloaded the raw versions of the files. If you use wget or curl be aware that github can send you a redirection page instead of a file. Use appropriate tool flag to avoid it.

> Note: On Mac OS all calls of the TONOS-CLI utility should be performed from the tonos-cli/target/release/ folder.

#### Tails OS secure environment

For maximum security while managing your wallet, you can use the Tails OS for all actions that can be performed offline. 

The following actions can be performed entirely offline:

* Generation of seed phrases and custodian keys
* New transaction preparation offline
* Preparing transaction confirmation offline

### 2.2. Set blockchain network

> Note: By default TONOS-CLI connects to net.ton.dev network.

Use the following command to switch to any other network

```
./tonos-cli config --url <https://network_url>
```

You need to do it only once before using the utility.

A .json configuration file will be created in the TONOS-CLI utility folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

## 3. Deploying Multisignature Wallet to the Blockchain
### 3.1. Generating seed phrases and custodian keys
> Note: All actions of this section should be performed for every custodian of the multisignature wallet.

#### 3.1.1. Generating seed phrase
To generate your seed phrase enter the following command:
```
./tonos-cli genphrase
```
Terminal displays the generated seed phrase.
> Note: The seed phrase ensures access to the multisignature wallet. If lost, the custodian will no longer be able to manage the wallet. The seed phrase is unique for every custodian and should be kept secret and securely backed up.

#### 3.1.2. Generating public key
To generate your public key enter the following command with your previously generated seed phrase in quotes:
```
./tonos-cli genpubkey "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```
Copy the generated code from Terminal or scan the QR code containing the code with your phone and send it to whichever custodian is responsible for deploying the multisignature wallet.
> Note: The public key is not secret and can be freely transmitted to anyone.

### 3.2. Deploying Multisignature Wallet
Any custodian who has received the public keys of all other custodians can deploy the multisignature wallet to the blockchain.

#### 3.2.1. Generating multisignature wallet address and deployment key pair
To create the key pair file from the seed phrase generated at step 3.1.1  use the following command:
```
./tonos-cli getkeypair <deploy.keys.json> "<seed_phrase>"
```
`deploy.keys.json` - the file the key pair will be written to.
The utility generates the file that contains the key pair produced from seed phrase. Use it to generate your address:
```
./tonos-cli genaddr SafeMultisigWallet.tvc SafeMultisigWallet.abi.json --setkey deploy.keys.json --wc <workchain_id>
```
* `deploy.keys.json` - the file the key pair is read from.
* `--wc <workchain_id>` - (optional) ID of the workchain the wallet will be deployed to (-1 for masterchain, 0 for basechain). By default this value is set to 0.

> Note: Masterchain gas and storage fees are significantly higher, but masterchain is required for validator wallets. Make sure to set workchain ID to -1 for any validator wallets you are deploying: `--wc -1`. Basechain, on the other hand, is best suited for user wallets.

The utility displays the new multisignature wallet address (Raw_address).

> Note: The wallet address is required for any interactions with the wallet. It should be shared with all wallet custodians.

#### 3.2.2. (Optional) Check that a wallet with the address generated on the previous step does not already exist in the blockchain
Request status for the generated wallet address from the blockchain:
```
./tonos-cli account <multisig_address>
```
#### 3.2.3. Send a few tokens to the new address from another contract. 
Create, and if necessary, confirm a transaction from another wallet (see sections 4.6 and 4.7 of this document).
Ensure that multisignature wallet has been created in the blockchain and has Uninit status.
```
./tonos-cli account <multisig_address>
```

#### 3.2.4. Deploy the multisignature code and data to the blockchain
Use the following command:
```
./tonos-cli deploy SafeMultisigWallet.tvc '{"owners":["0x...", ...],"reqConfirms":N}' --abi SafeMultisigWallet.abi.json --sign deploy.keys.json --wc <workchain_id>
```
Configuration parameters:
* `owners` - array of custodian public keys as uint256 numbers. Make sure all public keys are enclosed in quotes and start with `0x...`. Example: `"owners":["0x8868adbf012ebc349ced852fdcf5b9d55d1873a68250fae1be609286ddb962582", "0xa0e16ccff0c7bf4f29422b33ec1c9187200e9bd949bb2dd4c7841f5009d50778a"]`
* `reqConfirms` - number of signatures needed to confirm a transaction ( 0 < N ≤ custodian count).
* `--wc <workchain_id>` - (optional) ID of the workchain the wallet will be deployed to (-1 for masterchain, 0 for basechain). By default this value is set to 0.

> Note: Masterchain gas and storage fees are significantly higher, but masterchain is required for validator wallets. Make sure to set workchain ID to -1 for any validator wallets you are deploying: `--wc -1`. Basechain, on the other hand, is best suited for user wallets.

#### 3.2.5. Check the multisignature wallet status again
Now it should be Active.
```
./tonos-cli account <multisig_address>
```

#### 3.2.6. Request the list of custodian public keys from the blockchain
Verify that they match the keys you have loaded during deploy.
```
./tonos-cli run <multisig_address> getCustodians {} --abi SafeMultisigWallet.abi.json
```
The wallet is deployed and the owners of the listed public keys have access to it.

## 4. Online Multisignature Wallet Management
### 4.1. Selecting blockchain network

> Note: By default TONOS-CLI connects to net.ton.dev network.

Use the following command to switch to any other network 
```
./tonos-cli config --url <https://network_url>
```
You need to do it only once before using the utility.

A .json configuration file will be created in the TONOS-CLI utility folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

### 4.2. Token to nanotoken conversion

Amounts in multisignature transactions are indicated in nanotokens. To convert tokens to nanotokens use the following command:
```
./tonos-cli convert tokens <amount>
```

### 4.3. Querying the status of the multisignature wallet in the blockchain

You may use the following command to check the current status and balance of your wallet. 
```
./tonos-cli account <multisig_address>
```
It displays the wallet status:
* `Not found` – if the wallet does not exist
* `Uninit` – wallet was created, but contract code wasn’t deployed
* `Active` – wallet exists and has the contract code and data
It also displays the wallet balance, time of the most recent transaction and contract data block.

### 4.4. Requesting the list of custodian public keys from the blockchain
The following command displays the list of public keys, the owners of which have rights to manage the wallet:
```
./tonos-cli run <multisig_address> getCustodians {} --abi SafeMultisigWallet.abi.json
```

### 4.5. Listing transactions awaiting confirmation
Use the following command to list the transactions currently awaiting custodian confirmation:
```
./tonos-cli run <multisig_address> getTransactions {} --abi SafeMultisigWallet.abi.json
```
If there are some transactions requiring confirmation, they will be displayed.

### 4.6 Creating transaction online
Use the following command to create a new transaction:
```
./tonos-cli call <multisig_address> submitTransaction '{"dest":"raw_address","value":<nanotokens>,"bounce":true,"allBalance":false,"payload":""}' --abi SafeMultisigWallet.abi.json --sign "<seed_phrase>"
```
* `"dest"` - raw address of a destination smart contract. Example: `"0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3"`
* `"value":` - amount of tokens to transfer in nanotokens (Example: "value":10000000000 sets up a transfer of 10 tokens).
* `"bounce"` - use false to transfer funds to a non-existing contract to create it. use true to transfer funds to an Active contract.
* `"allBalance"` - use true (and value = 0) if you need to transfer all contract funds. Don't use value equal to contract balance to send all remaining tokens, such transaction will fail because before the value is subtracted from balance, gas and storage fees are consumed and the remaining balance will be less than value.
* `"payload"` - use "" for simple transfer. Otherwise payload is used as a body of outbound internal message.
Enter your seed phrase to sign the message with your key.

> Note: For maximum security you may also create a transaction message on a machine without internet connection in offline mode. See section 5.1 of this document.

### 4.7. Creating transaction confirmation online
Once one of the custodians creates a new transaction on the blockchain, it has to get the required number of confirmations from other custodians.

To create a confirmation message use the following command:
```
./tonos-cli call <multisig_address> confirmTransaction '{"transactionId":"<id>"}' --abi SafeMultisigWallet.abi.json --sign "<seed_phrase>"
```
`transactionId` – the ID of the transaction can be acquired from the custodian who created it, or by requesting the list of transactions awaiting confirmation from the multisignature wallet.

> Note: If the wallet has only one custodian, or if the number or confirmations required to perform a transaction was set to 1, this action won't be necessary. The transaction will be confirmed automatically.
> Note: For maximum security you may also create a transaction confirmation message on a machine without internet connection in offline mode. See section 5.2 of this document.

### 4.8. Broadcasting previously generated message
Use the following command to broadcast any previously generated message (transaction message or confirmation message):
```
./tonos-cli send --abi SafeMultisigWallet.abi.json "message"
```
`Message` – the content of the message code generated by the TONOS-CLI utility during message creation. It should be enclosed in double quotes.

## 5. Offline Multisignature Wallet Management
### 5.1. Creating new transaction offline
An internet connection is not required to create a signed transaction message. Use to following command to do it:
```
./tonos-cli message <multisig_address> submitTransaction '{"dest":"raw_address","value":<nanotokens>,"bounce":true,"allBalance":false,"payload":""}' --abi SafeMultisigWallet.abi.json --sign "<seed_phrase>" --lifetime 3600
```
* `"dest"` - raw address of a destination smart contract. Example: `"0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3".`
* `"value":` - amount of tokens to transfer in nanotokens (Example: "value":10000000000 sets up a transfer of 10 tokens).
* `"bounce"` - use false to transfer funds to a non-existing contract to create it. use true to transfer funds to an Active contract.
* `"allBalance"` - use true (and value = 0) if you need to transfer all contract funds. Don't use value equal to contract balance to send all remaining tokens, such transaction will fail because before the value is subtracted from balance, gas and storage fees are consumed and the remaining balance will be less than value.
* `"payload"` - use "" for simple transfer. Otherwise payload is used as a body of outbound internal message.
Enter your seed phrase to sign the message with your key.
* `lifetime` – message lifetime in second. Once this time elapses, the message will not be accepted by the contract.

The TONOS-CLI utility displays encrypted transaction text and a QR code that contains the submitTransaction message.
Copy the message text or scan the QR code and broadcast the message online.

### 5.2. Creating transaction confirmation offline
Once one of the custodians creates a new transaction on the blockchain, it has to get the required number of confirmations from other custodians.
To create a confirmation message offline use the following command:
```
./tonos-cli message <multisig_address> confirmTransaction '{"transactionId":"<id>"}' --abi SafeMultisigWallet.abi.json --sign "<seed_phrase>" --lifetime 600
```
`transactionId` – the ID of the transaction can be acquired from the custodian who created it, or by requesting the list of transactions awaiting confirmation from the multisignature wallet.

The TONOS-CLI utility displays encrypted transaction text and a QR code that contains the confirmTransaction message.
Copy the message text or scan the QR code and broadcast the message online.
