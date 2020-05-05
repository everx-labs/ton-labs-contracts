# Working with Multisignature Wallet

## Introduction

You can use the TONOS-CLI utility and [Tails OS](https://tails.boum.org/) to deploy multisignature wallets and manage them.

Available actions with Multisignature wallet include the following:

1. Contract initialization: generation of seed phrases and custodian keys – **OFFLINE**
2. Wallet deploy – **ONLINE**
3. New transaction preparation – **OFFLINE**
4. Broadcasting the prepared transaction to the multisignature wallet – **ONLINE**
5. Preparing transaction confirmation – **OFFLINE**
6. Broadcasting confirmation to multisignature wallet – **ONLINE**

## Creating secure environment

All offline actions with a multisignature wallet require a secure environment.

Follow all the steps of the [Creating secure environment with Tails OS and TONOS-CLI](https://github.com/tonlabs/ton-labs-contracts/blob/master/solidity/safemultisig/SecureEnv.md) document to create such an environment based on the Tails OS.

## Deploying Multisignature Wallet to TON blockchain

### Generating seed phrases and custodian keys

Boot Tails OS and open Terminal, navigate to the folder with the TONOS-CLI utility.

> **Note**: all actions of this section should be performed for every custodian of the multisignature wallet.

> **Note**: All actions of this section are performed OFFLINE.

#### Generating seed phrase

To generate your seed phrase enter the following command:

```jsx
./tonos-cli genphrase
```

Terminal displays the generated seed phrase.

> **Note**: The seed phrase ensures access to the multisignature wallet. If lost, the custodian will no longer be able to manage the wallet. The seed phrase is unique for every custodian and should be kept secret and securely backed up.

#### Generating public key

To generate your public key enter the following command with your previously generated seed phrase in quotes:

```jsx
./tonos-cli genpubkey "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```
Scan the resulting QR code with your phone and send it to whichever custodian is responsible for deploying the multisignature wallet.

> **Note**: The public key is not secret and can be freely transmitted to anyone.

### Deploying Multisignature Wallet

Any custodian who has received the public keys of all other custodians can deploy the multisignature wallet to the blockchain.

#### Querying the status of the multisignature wallet in the blockchain

You may use the following command to verify the intermediate steps of the wallet deploy procedure:

```jsx
./tonos-cli account <multisig_address>
```
It displays the wallet status:

- **Not found** – if the wallet does not exist
- **Uninit** – wallet was created, but contract code wasn’t deployed
- **Active** – wallet exists and has the contract code and data

It also displays the wallet balance, time of the most recent transaction and contract data block.

#### Deployment procedure

1. Generate the future multisignature address:

```jsx
./tonos-cli genaddr SafeMultisigWallet.tvc SafeMultisigWallet.abi.json --genkey deploy.keys.json
```
The utility displays the new multisignature address and generates the `deploy.keys.json` file that contains the key pair with which to sign the deploy message.

2. (Optional) Ensure a wallet with this address does not already exist in the blockchain.

```jsx
./tonos-cli account <multisig_address>
```

3. Send a few tokens to the new address from another contract. Ensure that multisignature wallet has been created in the blockchain and has **Uninit** status.

```jsx
./tonos-cli account <multisig_address>
```

4. Configure multisignature wallet and send the multisignature code and data to the blockchain.

```jsx
./tonos-cli deploy SafeMultisigWallet.tvc '{"owners":["0x...", ...],"reqConfirms":N}' --abi SafeMultisigWallet.abi.json --sign deploy.keys.json
```

Configuration parameters:

`owners` - list of custodian public keys.

`reqConfirms` - number of signatures needed to confirm a transaction ( 0 < N ≤ custodian count).

5. Check the multisignature wallet status. It should be **Active**.

```jsx
./tonos-cli account <multisig_address>
```

6. Request the list of custodian public keys from the blockchain. Verify that they match the keys you have loaded during deploy.

```jsx
./tonos-cli run <multisig_address> getCustodians {} --abi SafeMultisigWallet.abi.json
```

## Offline Multisignature Wallet Management

### Token to nanotoken conversion

Amounts in multisignature transactions are indicated in nanotokens. To convert tokens to nanotokens use the following command:

```jsx
./tonos-cli convert tokens <amount>
```

### Creating new transaction offline

An internet connection is not required to create a signed transaction message. Use to following command to do it:

```jsx
./tonos-cli message <multisig_address> submitTransaction '{"dest":"raw_address","value":<nanotokens>,"bounce":true,"allBalance":false,"payload":""}' --abi SafeMultisigWallet.abi.json --sign "<seed_phrase>" --lifetime 3600
```

Enter your seed phrase to sign the message with your key.

`lifetime` – message lifetime in second. Once this time elapses, the message will not be accepted by the contract.

The TONOS-CLI utility displays a QR code that contains the `submitTransaction` message.

Scan the resulting QR code and broadcast the message it contains to the multisignature wallet later via TONOS-CLI (see *Broadcasting previously generated message* section below).

### Creating transaction confirmation offline

Once one of the custodians creates a new transaction on the blockchain, it has to get the required number of confirmations from other custodians.

To create a confirmation message use the following command:

```jsx
./tonos-cli message <multisig_address> confirmTransaction '{"transactionId":"<id>"}' --abi SafeMultisigWallet.abi.json --sign "<seed_phrase>" --lifetime 600
```

`transactionId` – the ID of the transaction can be acquired from the custodian who created it, or by requesting the list of transactions awaiting confirmation from the multisignature wallet.

As with the transaction message above, the TONOS-CLI utility displays a QR code that contains the message. Scan the QR code and broadcast the message it contains to the multisignature wallet later via TONOS-CLI (see *Broadcasting previously generated message* section below).

## Online Multisignature Wallet Management

### Selecting blockchain network

> Note: By default TONOS-CLI connects to net.ton.dev network.

Use the following command to switch to the main net network (whenever available):

```jsx
./tonos-cli config --url https://mainnet.ton.dev
```

You need to do it only once before using the utility.

`tonlabs-cli.conf.json` configuration file will be created in the TONOS-CLI utility folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

### Listing transactions awaiting confirmation

Use the following command to list the transactions currently awaiting custodian confirmation:

```jsx
./tonos-cli run <multisig_address> getTransactions {} --abi SafeMultisigWallet.abi.json
```

The screenshot above is an example of an empty transaction list. Nothing currently needs confirmation.

If there are some transactions requiring confirmation, they will be displayed:

### Broadcasting previously generated message

Use the following command to broadcast any previously generated message:

```jsx
./tonos-cli send --abi SafeMultisigWallet.abi.json "message"
```

`Message` – the content of the QR code generated by the TONOS-CLI utility during message creation. It should be enclosed in double quotes.

Example of a message with a new transaction being broadcasted to the multisignature wallet:

The terminal displays the result of new transaction creation:

```jsx
Result: {
"transId": "0x5ea98b30fb3f0041"
}
```

To receive confirmations from the required number of fellow wallet custodians, send them this transaction ID.
