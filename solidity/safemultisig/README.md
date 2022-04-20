# Multisignature Wallet
SafeMultisigWallet - formally verified multisignature wallet. Compiled by [TON Solidity Compiler](https://github.com/tonlabs/TON-Solidity-Compiler) (v 0.21 commit 1657b4f3541f19f3d23f87ac32800efe714bccc7).

Multisignature wallet is a crypto wallet on the blockchain, which supports multiple owners (custodians), who are authorized to manage the wallet.

You can use the [TONOS-CLI](https://github.com/tonlabs/tonos-cli) utility to deploy multisignature wallets and manage them.

# Table of Contents
- [1. Introduction](#1-introduction)
  - [Glossary](#glossary)
- [2. Install TONOS-CLI](#2-install-tonos-cli)
  - [2.1. Install TONOS-CLI utility](#21-install-tonos-cli-utility)
    - [Install compiled executable](#install-compiled-executable)
    - [Install through TONDEV](#install-through-tondev)
    - [Build from source](#build-from-source)
    - [Tails OS secure environment](#tails-os-secure-environment)
    - [A note on Windows syntax](#a-note-on-windows-syntax)
  - [2.2. Download contract files](#22-download-contract-files)
  - [2.3. Configure TONOS-CLI environment](#23-configure-tonos-cli-environment)
- [3. Create Wallet](#3-create-wallet)
  - [3.1. Create seed phrases and public keys for all custodians](#31-create-seed-phrases-and-public-keys-for-all-custodians)
    - [3.1.1. Create wallet seed phrase](#311-create-wallet-seed-phrase)
    - [3.1.2. Generate public key](#312-generate-public-key)
  - [3.2. Generate deployment key pair file](#32-generate-deployment-key-pair-file)
  - [3.3. Generate wallet address](#33-generate-wallet-address)
  - [3.4. Send tokens to the new address from another wallet](#34-send-tokens-to-the-new-address-from-another-wallet)
  - [3.5. Deploy wallet (set custodians)](#35-deploy-wallet-set-custodians)
    - [3.5.1. Deploy the wallet to blockchain](#351-deploy-the-wallet-to-blockchain)
    - [3.5.2. Check that the wallet is active](#352-check-that-the-wallet-is-active)
    - [3.5.3. Request the list of custodian public keys from the blockchain](#353-request-the-list-of-custodian-public-keys-from-the-blockchain)
- [4. Manage Wallet](#4-manage-wallet)
  - [4.1. Select blockchain network](#41-select-blockchain-network)
  - [4.2. Convert tokens to nanotokens](#42-convert-tokens-to-nanotokens)
  - [4.3. Check wallet balance and status](#43-check-wallet-balance-and-status)
    - [4.3.1. Check wallet balance and status with TONOS-CLI](#431-check-wallet-balance-and-status-with-tonos-cli)
    - [4.3.2. Check wallet balance and status in the blockchain explorer](#432-check-wallet-balance-and-status-in-the-blockchain-explorer)
  - [4.4. List custodian public keys](#44-list-custodian-public-keys)
  - [4.5. List transactions awaiting confirmation](#45-list-transactions-awaiting-confirmation)
  - [4.6. Create transaction online](#46-create-transaction-online)
    - [4.6.1. Alternative command to create transaction online](#461-alternative-command-to-create-transaction-online)
  - [4.7. Create transaction confirmation online](#47-create-transaction-confirmation-online)
    - [4.7.1. Alternative command to confirm transaction online](#471-alternative-command-to-confirm-transaction-online)
  - [4.8. Create new transaction offline](#48-create-new-transaction-offline)
  - [4.9. Create transaction confirmation offline](#49-create-transaction-confirmation-offline)
  - [4.10. Generate deploy message offline](#410-generate-deploy-message-offline)
  - [4.11. Broadcast previously generated message](#411-broadcast-previously-generated-message)
- [5. Error codes](#5-error-codes)


# 1. Introduction

Multisignature wallets are implemented as decentralized smart contracts. All wallet data is stored on the blockchain. 

Multisignature wallets can have up to 32 custodians.

By default they can queue up to 5 transactions from each single custodian to be confirmed by other custodians.

Default transaction lifetime is 1 hour.

Minimal amount that can be transferred is 0.001 tokens (1000000 nanotokens).

## Glossary

`Multisignature wallet` - crypto wallet on the blockchain, which supports multiple owners (custodians), who are authorized to manage the wallet.

`Wallet address` - unique address of the wallet on the blockchain. It explicitly identifies the wallet and is required for any actions with the wallet to be performed. It does not, on its own, provide anyone access to wallet funds.

`Wallet custodian` - authorized owner of the wallet. Owns the private key and corresponding seed phrase, which are required to make any changes to the wallet or wallet funds. Wallet may have more than one custodian.

`Custodian private key` - the unique cryptographic key belonging to the wallet custodian, which authorizes access to the wallet. Should be kept secret.

`Custodian seed phrase` - unique mnemonic phrase exactly corresponding to the custodian private key. Can be used to restore the private key, or to sign transactions in TONOS-CLI instead of it. Should be kept secret and securely backed up.

`Custodian public key` - public key forming a cryptographic key pair with the custodian private key. It is not secret and may be freely shared with anyone.

`Validator` - the entity performing validation of new blocks on the blockchain through a Proof-of-Stake system. Requires a multisignature wallet for staking.

# 2. Install TONOS-CLI
## 2.1. Install TONOS-CLI utility
### Install compiled executable

Create a folder. Download the `.zip` file from the latest release from here: [https://github.com/tonlabs/tonos-cli/releases](https://github.com/tonlabs/tonos-cli/releases) to this folder. Extract it.

### Install through TONDEV

You can use [TONDEV](https://github.com/tonlabs/tondev) to install the latest version of TONOS-CLI.

```bash
tondev tonos-cli install
```

The installer requires [NPM](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm) to be installed, so it can install packages globally without using sudo. In case of error, manually set environment variable `PATH=$PATH:$HOME./tondev/solidity`

This command updates TONOS-CLI installed through TONDEV to the latest version:

```bash
tondev tonos-cli update
```

This command specifies TONOS-CLI version to use and downloads it if needed:

```bash
tondev tonos-cli set --version 0.8.0
```

### Build from source

Refer to the [TONOS-CLI readme](https://github.com/tonlabs/tonos-cli#build-from-source) for build from source procedure.

### Tails OS secure environment

For maximum security while working with offline TONOS-CLI features (such as cryptographic commands or encrypted message generation), you can use the [Tails OS](https://tails.boum.org/).

You can perform the following actions entirely offline:

* Generate [seed phrases and custodian keys](#31-create-seed-phrases-and-public-keys-for-all-custodians)
* Pepare [deployment message](#411-broadcast-previously-generated-message) offline
* Prepare [new transaction](#48-create-new-transaction-offline) offline
* Prepare [transaction confirmation](#49-create-transaction-confirmation-offline) offline

### A note on Windows syntax

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


## 2.2. Download contract files 

Download compiled `.abi.json` and `.tvc` multisignature contract files from https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity

Choose a contract version:

* **SafeMultisig** - basic multisignature wallet, does not permit contract code modification. Is required if you use validator scripts.

`SafeMultisigWallet.abi.json` direct link:

https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/master/solidity/safemultisig/SafeMultisigWallet.abi.json

 `SafeMultisigWallet.tvc` direct link:

https://github.com/tonlabs/ton-labs-contracts/raw/master/solidity/safemultisig/SafeMultisigWallet.tvc

* **SetcodeMultisig** - more advanced multisignature wallet.

`SetcodeMultisigWallet.abi.json` direct link:

https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/master/solidity/setcodemultisig/SetcodeMultisigWallet.abi.json

`SetcodeMultisigWallet.tvc` direct link:

https://github.com/tonlabs/ton-labs-contracts/raw/master/solidity/setcodemultisig/SetcodeMultisigWallet.tvc

Place both files into the folder containing the `tonos-cli` executable.

> **Note**: Make sure you have downloaded the **raw** versions of the files. A common error when downloading from the github project page manually is to save the redirection page instead of the raw file.

> **Note**: [TON Surf](https://ton.surf/) uses a specialized version of the SetcodeMultisig contract. It will not be possible to manage a standard Setcode wallet in TON Surf.


## 2.3. Configure TONOS-CLI environment

1. (Optional, Linux/Mac OS, if you didn't install through tondev) Put `tonos-cli` into system environment:
```
export PATH="<tonos_folder_path>:$PATH"
```
If you skip this step and didn't install through [tondev](#install-through-tondev), make sure you run the utility from the utility folder: 
```
./tonos-cli <command> <options>
```

2. Use the following command to set the network:
```
tonos-cli config --url <https://network_url>
```
Some of the frequently used networks:

`https://net.ton.dev` - developer sandbox for testing.

`https://main.ton.dev` - main Free TON network.

`https://rustnet.ton.dev` - test network running on Rust nodes.

You need to do it only once before using the utility.

`tonos-cli.conf.json` configuration file will be created in the current folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

> **Note**: By default `tonos-cli` connects to `net.ton.dev` network.

> **Note**: Always run `tonos-cli` utility only from the folder where `tonos-cli.conf.json` is placed, unless you have configured a different path for the file. Refer to the [TONOS-CLI document](https://github.com/tonlabs/tonos-cli#24-override-configuration-file-location) for additional information.

3. Use the following command to check the set network:

       tonos-cli config --list

For additional configuration options, refer to the [TONOS-CLI readme](https://github.com/tonlabs/tonos-cli#2-configuration).


# 3. Create Wallet

The following actions should be performed to create a wallet:

1. Create wallet seed phrase
2. Generate deployment key pair file with wallet private/public keys based on the wallet seed phrase
3. Generate wallet address based on the wallet seed phrase
4. Send some tokens to the wallet address
5. Deploy wallet (set custodians)

All of these steps are detailed in this section.

## 3.1. Create seed phrases and public keys for all custodians
### 3.1.1. Create wallet seed phrase

To generate your seed phrase enter the following command:
```
tonos-cli genphrase
```
Terminal displays the generated seed phrase.

Example:

```bash
$ tonos-cli genphrase
Config: /home/user/tonos-cli.conf.json
Succeeded.
Seed phrase: "rule script joy unveil chaos replace fox recipe hedgehog heavy surge online"
```

> **Note**: Seed phrases should be created for every custodian of the multisignature wallet.

> The seed phrase ensures access to the multisignature wallet. If lost, the custodian will no longer be able to manage the wallet. The seed phrase is unique for every custodian and should be kept secret and securely backed up (word order matters).

### 3.1.2. Generate public key

To generate your public key enter the following command with your previously generated seed phrase in quotes:
```
tonos-cli genpubkey "<seed_phrase>"
```

Example:

```bash
$ tonos-cli genpubkey "rule script joy unveil chaos replace fox recipe hedgehog heavy surge online"
Config: /home/user/tonos-cli.conf.json
Succeeded.
Public key: 88c541e9a1c173069c89bcbcc21fa2a073158c1bd21ca56b3eb264bba12d9340

<QR code with key>                                         

```
Copy the generated code from Terminal or scan the QR code containing the code with your phone and send it to whichever custodian is responsible for deploying the multisignature wallet.

> **Note**: The public key should also be generated for every custodian. The public key is not secret and can be freely transmitted to anyone.

## 3.2. Generate deployment key pair file

Any custodian who has received the public keys of all other custodians can deploy the multisignature wallet to the blockchain.

To create the key pair file from the seed phrase generated at step **3.1.1** use the following command:
```
tonos-cli getkeypair <deploy.keys.json> "<seed_phrase>"
```
`<deploy.keys.json>` - the file the key pair will be written to.

The utility generates the file that contains the key pair produced from seed phrase.

```bash
$ tonos-cli getkeypair key.json "rule script joy unveil chaos replace fox recipe hedgehog heavy surge online"
Config: /home/user/tonos-cli.conf.json
Input arguments:
key_file: key.json
  phrase: rule script joy unveil chaos replace fox recipe hedgehog heavy surge online
Succeeded.
```

## 3.3. Generate wallet address

Use deployment key pair file to generate your address:
```
tonos-cli genaddr <MultisigWallet.tvc> --setkey <deploy.keys.json> --wc <workchain_id> --abi <MultisigWallet.abi.json>
```
`<MultisigWallet.tvc>` - either `SafeMultisigWallet.tvc` or `SetcodeMultisigWallet.tvc` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<deploy.keys.json>` - the file the key pair is read from.

`--wc <workchain_id>` - (optional) ID of the workchain the wallet will be deployed to (`-1` for masterchain, `0` for basechain). By default this value is set to `0`.

> **Note**: Masterchain fees are significantly higher, but masterchain is required for direct staking validator wallets. Make sure to set workchain ID to `-1` for any direct staking validator wallets you are deploying: `--wc -1`. Basechain, on the other hand, is best suited for user wallets and validator wallets that are staking through a [DePool](https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/depool).

The utility displays the new multisignature wallet address (Raw_address).

Example:

```bash
$ tonos-cli genaddr --genkey key.json --wc -1 --abi SafeMultisigWallet.abi.json SafeMultisigWallet.tvc
Config: /home/user/tonos-cli.conf.json
Input arguments:
     tvc: SafeMultisigWallet.tvc
      wc: -1
    keys: key.json
init_data: None
is_update_tvc: None

Seed phrase: "chimney nice diet engage hen sing vocal upgrade column address consider word"
Raw address: -1:a021414a79539001ed35d615a646dc8b89df29ccccf143c30df15c7fbcaff086
testnet:
Non-bounceable address (for init): 0f-gIUFKeVOQAe011hWmRtyLid8pzMzxQ8MN8Vx_vK_whkeM
Bounceable address (for later access): kf-gIUFKeVOQAe011hWmRtyLid8pzMzxQ8MN8Vx_vK_whhpJ
mainnet:
Non-bounceable address (for init): Uf-gIUFKeVOQAe011hWmRtyLid8pzMzxQ8MN8Vx_vK_whvwG
Bounceable address (for later access): Ef-gIUFKeVOQAe011hWmRtyLid8pzMzxQ8MN8Vx_vK_whqHD
Succeeded
```

> **Note**: The wallet address is required for any interactions with the wallet. It should be shared with all wallet custodians.


## 3.4. Send tokens to the new address from another wallet

Use the following command to create a new transaction from another existing wallet:
```
tonos-cli call <source_address> submitTransaction '{"dest":"<raw_address>","value":<nanotokens>,"bounce":false,"allBalance":false,"payload":""}' --abi <MultisigWallet.abi.json> --sign "<source_seed_or_keyfile>"
```
`<source_address>` - address of the wallet the funds are sent from.

`"dest":<raw_address>` - new wallet address generated at step **3.3**. Example: `"0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3"`

`"value"`: - amount of tokens to transfer in nanotokens (Example: `"value":10000000000` sets up a transfer of 10 tokens).

`"bounce"` - use `false` to transfer funds to a non-existing contract to create it.

`"payload"` - use "" for simple transfer. Otherwise payload is used as a body of outbound internal message.

`"allBalance"` - used to transfer all funds in the wallet. Use `false` for a simple transfer.

> **Note**: Due to a bug setting `allBalance` to `true` currently causes errors. Single-custodian multisig wallets may use `sendTransaction` method with flag `130` and value `0` instead:
```
tonos-cli call <multisig_address> sendTransaction '{"dest":"raw_address","value":0,"bounce":true,"flags":130,"payload":""}' --abi <MultisigWallet.abi.json> --sign <seed_or_keyfile>
```

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`"<source_seed_or_keyfile>"` - seed phrase in quotes or path to keyfile of the source wallet.

Example:

```bash
$ tonos-cli call 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc submitTransaction '{"dest":"-1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6","value":234000000,"bounce":false,"allBalance":false,"payload":""}' --abi SetcodeMultisigWallet.abi.json --sign k1.keys.json
Config: /home/user/tonos-cli.conf.json
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: submitTransaction
  params: {"dest":"-1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6","value":234000000,"bounce":false,"allBalance":false,"payload":""}
     abi: SetcodeMultisigWallet.abi.json
    keys: k1.keys.json
lifetime: None
  output: None
Connecting to net.ton.dev
Generating external inbound message...

MessageId: c6baac843fefe6b9e8dc3609487a63ef21207e4fdde9ec253b9a47f7f5a88d01
Expire at: Sat, 08 May 2021 14:52:23 +0300
Processing... 
Succeeded.
Result: {
  "transId": "6959885776551137793"
}
```

If the sponsoring wallet has multiple custodians, the transaction may require confirmation from its other custodians.


To confirm the transaction use the following command:
```
tonos-cli call <source_address> confirmTransaction '{"transactionId":"<id>"}' --abi <MultisigWallet.abi.json> --sign "<source_seed_or_keyfile>"
```
`<source_address>` - address of the wallet to funds are sent from.

`"<source_seed_or_keyfile>"` - seed phrase in quotes or path to keyfile of the source wallet.

`transactionId` – the ID of the transaction transferring tokens to the new  wallet.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).


Example:

```
$ tonos-cli call 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc confirmTransaction '{"transactionId":"6981478983724354305"}' --abi SetcodeMultisigWallet.abi.json --sign k2.keys.json
Config: default
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: confirmTransaction
  params: {"transactionId":"6981478983724354305"}
     abi: SetcodeMultisigWallet.abi.json
    keys: k2.keys.json
lifetime: None
  output: None
Connecting to https://net.ton.dev
Generating external inbound message...

MessageId: 322e1efffedf73c8009b84a103dd3fdc205796eb4d88a912fa13d931ce9e7c9c
Expire at: Mon, 05 Jul 2021 19:28:08 +0300
Processing... 
Succeeded.
Result: {}
```

Ensure that the new wallet has been created in the blockchain and has **Uninit** status:

```
tonos-cli account <multisig_address>
```
`<multisig_address>` - new wallet address generated at step **3.3**.


## 3.5. Deploy wallet (set custodians)
### 3.5.1. Deploy the wallet to blockchain

Use the following command:
```
tonos-cli deploy <MultisigWallet.tvc> '{"owners":["0x...", ...],"reqConfirms":N}' --abi <MultisigWallet.abi.json> --sign <deploy_seed_or_keyfile> --wc <workchain_id>
```
Configuration parameters:

`<MultisigWallet.tvc>` - either `SafeMultisigWallet.tvc` or `SetcodeMultisigWallet.tvc` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

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

Example:

```bash
$ tonos-cli deploy --sign key.json --wc -1 --abi SafeMultisigWallet.abi.json SafeMultisigWallet.tvc '{"owners":["0x88c541e9a1c173069c89bcbcc21fa2a073158c1bd21ca56b3eb264bba12d9340"],"reqConfirms":1}'
Config: /home/user/tonos-cli.conf.json
Input arguments:
     tvc: SafeMultisigWallet.tvc
  params: {"owners":["0x88c541e9a1c173069c89bcbcc21fa2a073158c1bd21ca56b3eb264bba12d9340"],"reqConfirms":1}
     abi: SafeMultisigWallet.abi.json
    keys: key.json
      wc: -1
Connecting to net.ton.dev
Deploying...
Transaction succeeded.
Contract deployed at address: -1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6
```

> **Note**: After a SafeMultisig wallet is deployed, for reasons of security you cannot add or remove custodians from it. If you want to change the custodian list, you have to create a new wallet, transfer all funds there, and set the new list of custodians.

### 3.5.2. Check that the wallet is active

Check the new wallet status again. Now it should be **Active**.

```
tonos-cli account <multisig_address>
```

### 3.5.3. Request the list of custodian public keys from the blockchain

Verify that they match the keys you have loaded during deploy.
```
tonos-cli run <multisig_address> getCustodians {} --abi SafeMultisigWallet.abi.json
```
The wallet is deployed and the owners of the listed public keys have access to it.

Example:

```
$ tonos-cli run 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc getCustodians {} --abi SetcodeMultisigWallet.abi.json
Config: default
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: getCustodians
  params: {}
     abi: SetcodeMultisigWallet.abi.json
    keys: None
lifetime: None
  output: None
Connecting to https://net.ton.dev
Generating external inbound message...

MessageId: 6c3daeeea601ef6c81a516079a3cec2210fea278a06cc7bb118b4529f154e5d7
Expire at: Mon, 05 Jul 2021 19:31:47 +0300
Running get-method...
Succeeded.
Result: {
  "custodians": [
    {
      "index": "1",
      "pubkey": "0x154bc7ed3088294e4e767e2e7183f43d62bcec820c58a30e2ec730f0bb8792a3"
    },
    {
      "index": "4",
      "pubkey": "0x18331765f53c6a50aa3a348fa4536e6f632798d81ff59281aae21d9b5f86a21c"
    },
    {
      "index": "3",
      "pubkey": "0x6ee6539d0d8a3800d7525922c25b64874e0645340f2b43a2cb277db458b42fa4"
    },
    {
      "index": "0",
      "pubkey": "0x849ee401fde65ad8cda6d937bdc81e2beba0f36ba2f87115f4a2d24a15568203"
    },
    {
      "index": "2",
      "pubkey": "0x9ef666feaacf1d65c78af3b1c099c5096aa2e26afc21346fd66b8e7d5d9d6224"
    }
  ]
}
```

# 4. Manage Wallet
## 4.1. Select blockchain network

There are two networks currently available:

Some of the frequently used networks:

`https://net.ton.dev` - developer sandbox for testing.

`https://main.ton.dev` - main Free TON network.

`https://rustnet.ton.dev` - test network running on Rust nodes.

Use the following command to switch to any of these networks:

```
tonos-cli config --url <https://network_url>
```

You need to do it only once before using the utility.

A `.json` configuration file will be created in the current folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

##  4.2. Convert tokens to nanotokens

Amounts in  most multisig wallet commands are indicated in nanotokens. To convert tokens to nanotokens use the following command:
```
tonos-cli convert tokens <amount>
```

Example:

```bash
$ tonos-cli convert tokens 125.8
Config: /home/user/tonos-cli.conf.json
125800000000
```

## 4.3. Check wallet balance and status
### 4.3.1. Check wallet balance and status with TONOS-CLI

You may use the following command to check the current status and balance of your wallet:
```
tonos-cli account <multisig_address>
```
It displays the wallet status:

* `Not found` – if the wallet does not exist
* `Uninit` – wallet was created, but contract code wasn’t deployed
* `Active` – wallet exists and has the contract code and data

It also displays the wallet balance, time of the most recent transaction, contract data block, data in boc format and code hash (which is unique for every contract type).

Example:

```bash
$ tonos-cli account 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
Config: default
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
Connecting to https://net.ton.dev
Processing...
Succeeded.
acc_type:      Active
balance:       236565978364 nanoton
last_paid:     1625502429
last_trans_lt: 0x9274fd9102
data(boc): b5ee9c7201020d010001b10003df849ee401fde65ad8cda6d937bdc81e2beba0f36ba2f87115f4a2d24a155682030000017a777eac3bc24f7200fef32d6c66d36c9bdee40f15f5d079b5d17c388afa5169250aab4101800000000000000000000000000000000000000000000000000000000000000082800000000182700c0a01020120050202016204030043bf3bd99bfaab3c75971e2bcec702671425aa8b89abf084d1bf59ae39f5767588900a0043bf127b9007f7996b63369b64def72078afae83cdae8be1c457d28b4928555a080c0202012007060044bfaee6539d0d8a3800d7525922c25b64874e0645340f2b43a2cb277db458b42fa40302016609080043bec198bb2fa9e3528551d1a47d229b737b193cc6c0ffac940d5710ecdafc3510e0240043beea5e3f6984414a7273b3f1738c1fa1eb15e7641062c5187176398785dc3c95180c01d7a030719912b7df6580b0719912b7df6580800000018201424f7200fef32d6c66d36c9bdee40f15f5d079b5d17c388afa5169250aab410180400255a3ad9dfa8aa4f3481856aafc7d79f47d50205190bd56147138740e9b177f30000000000000000000000000df28e800003c0b0000000140
code_hash: e2b60b6b602c10ced7ea8ede4bdf96342c97570a3798066f3fb50a4b2b27a208
```

SafeMultisig code hash is `80d6c47c4a25543c9b397b71716f3fae1e2c5d247174c52e2c19bd896442b105`

SetcodeMultisig code hash is `e2b60b6b602c10ced7ea8ede4bdf96342c97570a3798066f3fb50a4b2b27a208`

### 4.3.2. Check wallet balance and status in the blockchain explorer

The detailed status of the account can also be viewed in the [ton.live](https://ton.live/main) blockchain explorer.

Select the network the wallet is deployed to and enter the **raw address** of the wallet into the main search field.

Account status, balance, message and transaction history for the account will be displayed.

## 4.4. List custodian public keys

The following command displays the list of public keys, the owners of which have rights to manage the wallet:
```
tonos-cli run <multisig_address> getCustodians {} --abi <MultisigWallet.abi.json>
```

Example:

```
$ tonos-cli run 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc getCustodians {} --abi SetcodeMultisigWallet.abi.json
Config: default
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: getCustodians
  params: {}
     abi: SetcodeMultisigWallet.abi.json
    keys: None
lifetime: None
  output: None
Connecting to https://net.ton.dev
Generating external inbound message...

MessageId: 6c3daeeea601ef6c81a516079a3cec2210fea278a06cc7bb118b4529f154e5d7
Expire at: Mon, 05 Jul 2021 19:31:47 +0300
Running get-method...
Succeeded.
Result: {
  "custodians": [
    {
      "index": "1",
      "pubkey": "0x154bc7ed3088294e4e767e2e7183f43d62bcec820c58a30e2ec730f0bb8792a3"
    },
    {
      "index": "4",
      "pubkey": "0x18331765f53c6a50aa3a348fa4536e6f632798d81ff59281aae21d9b5f86a21c"
    },
    {
      "index": "3",
      "pubkey": "0x6ee6539d0d8a3800d7525922c25b64874e0645340f2b43a2cb277db458b42fa4"
    },
    {
      "index": "0",
      "pubkey": "0x849ee401fde65ad8cda6d937bdc81e2beba0f36ba2f87115f4a2d24a15568203"
    },
    {
      "index": "2",
      "pubkey": "0x9ef666feaacf1d65c78af3b1c099c5096aa2e26afc21346fd66b8e7d5d9d6224"
    }
  ]
}
```

## 4.5. List transactions awaiting confirmation

Use the following command to list the transactions currently awaiting custodian confirmation:

```
tonos-cli run <multisig_address> getTransactions {} --abi <MultisigWallet.abi.json>
```

If there are some transactions requiring confirmation, they will be displayed.

Example:

```bash
$ tonos-cli run 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc getTransactions {} --abi SafeMultisigWallet.abi.json
Config: /home/user/tonos-cli.conf.json
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: getTransactions
  params: {}
     abi: SafeMultisigWallet.abi.json
    keys: None
lifetime: None
  output: None
Connecting to net.ton.dev
Generating external inbound message...

MessageId: ff8b8a73b1a7803a735eb4f620cade78ed45fd1530992fd3bedb91f3c66eacc5
Expire at: Sat, 08 May 2021 15:16:59 +0300
Running get-method...
Succeeded.
Result: {
  "transactions": [
    {
      "id": "6959890394123980993",
      "confirmationsMask": "1",
      "signsRequired": "4",
      "signsReceived": "1",
      "creator": "0x849ee401fde65ad8cda6d937bdc81e2beba0f36ba2f87115f4a2d24a15568203",
      "index": "0",
      "dest": "-1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6",
      "value": "234000000",
      "sendFlags": "3",
      "payload": "te6ccgEBAQEAAgAAAA==",
      "bounce": false
    }
  ]
}
```

## 4.6. Create transaction online

Use the following command to create a new transaction:
```
tonos-cli call <multisig_address> submitTransaction '{"dest":"raw_address","value":<nanotokens>,"bounce":true,"allBalance":false,"payload":""}' --abi <MultisigWallet.abi.json> --sign <seed__or_keyfile>
```

`"dest"` - raw address of a destination smart contract. Example: `"0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3"`

`"value":` - amount of tokens to transfer in nanotokens (Example: `"value":10000000000` sets up a transfer of 10 tokens).

`"bounce"` - use `false` to transfer funds to a non-existing contract to create it. Use `true` to transfer funds to an Active contract.

> **Note**: at step [3.4]](#34-send-tokens-to-the-new-address-from-another-wallet) of the wallet deployment procedure use `false`.

`"payload"` - use "" for simple transfer. Otherwise payload is used as a body of outbound internal message.

`"allBalance"` - used to transfer all funds in the wallet. Use `false` for a simple transfer.

> **Note**: Due to a bug setting `allBalance` to `true` currently causes errors. Single-custodian multisig wallets may use `sendTransaction` method with flag `130` and value `0` instead:
```
tonos-cli call <multisig_address> sendTransaction '{"dest":"raw_address","value":0,"bounce":true,"flags":130,"payload":""}' --abi <MultisigWallet.abi.json> --sign <seed_or_keyfile>
```

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign keyfile.json`

If the wallet has multiple custodians and more than one custodian signature is required to execute a transaction, the new transaction is queued in the wallet and waits for the necessary amount of confirmations. Otherwise it is executed immediately.

Example:


```bash
$ tonos-cli call 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc submitTransaction '{"dest":"-1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6","value":234000000,"bounce":true,"allBalance":false,"payload":""}' --abi SetcodeMultisigWallet.abi.json --sign k1.keys.json
Config: /home/user/tonos-cli.conf.json
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: submitTransaction
  params: {"dest":"-1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6","value":234000000,"bounce":true,"allBalance":false,"payload":""}
     abi: SetcodeMultisigWallet.abi.json
    keys: k1.keys.json
lifetime: None
  output: None
Connecting to net.ton.dev
Generating external inbound message...

MessageId: c6baac843fefe6b9e8dc3609487a63ef21207e4fdde9ec253b9a47f7f5a88d01
Expire at: Sat, 08 May 2021 14:52:23 +0300
Processing... 
Succeeded.
Result: {
  "transId": "6959885776551137793"
}
```

> **Note**: For maximum security you may also create a transaction message on a machine without internet connection in offline mode. See section [4.8](#48-create-new-transaction-offline).


### 4.6.1. Alternative command to create transaction online

TONOS-CLI supports alterbative syntax for this command, which does not use quotes and brackets to list parameters and may be more convenient:

```bash
tonos-cli callex submitTransaction <multisig_address> <MultisigWallet.abi.json> <seed_or_keyfile> --dest <raw_address> --value <tokens>T --bounce <true|false> --allBalance <true|false> --payload ""
```

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`"flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`keyfile.json`

`<raw_address>` - raw address of a destination smart contract. Example: `0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3`

`value` - amount of tokens to transfer: in nanotokens, if specified without the `T` suffix, or in tokens, if specified with it (Example: `--value 10500000000` and `--value 10.5T` are the same value of 10.5 tokens).

`bounce` - use `false` to transfer funds to a non-existing contract to create it. Use `true` to transfer funds to an Active contract.

> **Note**: at step [3.4](#34-send-tokens-to-the-new-address-from-another-wallet) of the wallet deployment procedure use `false`.

`payload` - use "" for simple transfer. Otherwise payload is used as a body of outbound internal message.

`allBalance` - used to transfer all funds in the wallet. Use `false` for a simple transfer.

> **Note**: Due to a bug setting `allBalance` to `true` currently causes errors. Single-custodian multisig wallets may use `sendTransaction` method with flag `130` and value `0` instead:
```
tonos-cli callex sendTransaction <multisig_address> <MultisigWallet.abi.json> <seed_or_keyfile> --dest <raw_address> --value 0 --bounce <true|false> --flags 130 --payload ""
```

Example:

```bash
$ tonos-cli callex submitTransaction 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc SetcodeMultisigWallet.abi.json k1.keys.json --dest -1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6 --value 0.234T --bounce false --allBalance false --payload ""
Config: /home/user/tonos-cli.conf.json
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: submitTransaction
  params: {"dest":"-1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6","value":"0234000000","bounce":"false","allBalance":"false","payload":""}
     abi: SetcodeMultisigWallet.abi.json
    keys: k1.keys.json
Connecting to net.ton.dev
Generating external inbound message...

MessageId: a38f37bfbe3c7427c869b3ee97c3b2d7f4421ca1427ace4e7a92f1a61d7ef234
Expire at: Sat, 08 May 2021 15:10:15 +0300
Processing... 
Succeeded.
Result: {
  "transId": "6959890394123980993"
}
```

## 4.7. Create transaction confirmation online

Once one of the custodians creates a new transaction on the blockchain, it has to get the required number of confirmations from other custodians.

To confirm a transaction, use the following command:
```
tonos-cli call <multisig_address> confirmTransaction '{"transactionId":"<id>"}' --abi <MultisigWallet.abi.json> --sign <seed_or_keyfile>
```
`transactionId` – the ID of the transaction can be acquired from the custodian who created it, or by requesting the list of transactions awaiting confirmation from the multisignature wallet.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign keyfile.json`

> **Note**: If the wallet has only one custodian, or if the number of confirmations required to perform a transaction was set to 1, this action won't be necessary. The transaction will be confirmed automatically.

Example:

```
$ tonos-cli call 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc confirmTransaction '{"transactionId":"6981478983724354305"}' --abi SetcodeMultisigWallet.abi.json --sign k2.keys.json
Config: default
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: confirmTransaction
  params: {"transactionId":"6981478983724354305"}
     abi: SetcodeMultisigWallet.abi.json
    keys: k2.keys.json
lifetime: None
  output: None
Connecting to https://net.ton.dev
Generating external inbound message...

MessageId: 322e1efffedf73c8009b84a103dd3fdc205796eb4d88a912fa13d931ce9e7c9c
Expire at: Mon, 05 Jul 2021 19:28:08 +0300
Processing... 
Succeeded.
Result: {}
```

> **Note**: For maximum security you may also create a transaction confirmation message on a machine without internet connection in offline mode. See section [4.9](#49-create-transaction-confirmation-offline)

### 4.7.1. Alternative command to confirm transaction online

TONOS-CLI supports alterbative syntax for this command, which does not use quotes and brackets to list parameters and may be more convenient:

```bash
tonos-cli callex confirmTransaction <multisig_address> <MultisigWallet.abi.json> <seed_or_keyfile> --transactionId <id>
```

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`"flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`keyfile.json`

`<id>` - ID of the transaction that should be confirmed.

Example:

```bash
$ tonos-cli callex confirmTransaction 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc SetcodeMultisigWallet.abi.json k2.keys.json --transactionId 6982528395137505473
Config: default
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: confirmTransaction
  params: {"transactionId":"6982528395137505473"}
     abi: SetcodeMultisigWallet.abi.json
    keys: k2.keys.json
Connecting to https://net.ton.dev
Generating external inbound message...

MessageId: 00048660c32d95313eeee7e09d89679e0c68f9a7660794736ba399c4c5fab011
Expire at: Thu, 08 Jul 2021 15:26:26 +0300
Processing... 
Succeeded.
Result: {}
```


## 4.8. Create new transaction offline

An internet connection is not required to create a signed transaction message. Use the following command to do it:
```
tonos-cli message <multisig_address> submitTransaction '{"dest":"raw_address","value":<nanotokens>,"bounce":true,"allBalance":false,"payload":""}' --abi <MultisigWallet.abi.json> --sign <seed_or_keyfile> --lifetime 3600
```
`"dest"` - raw address of a destination smart contract. Example: `"0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3"`.

`"value":` - amount of tokens to transfer in nanotokens (Example: `"value":10000000000` sets up a transfer of 10 tokens).

`"bounce"` - use `false` to transfer funds to a non-existing contract to create it. Use `true` to transfer funds to an Active contract.

`"payload"` - use "" for simple transfer. Otherwise payload is used as a body of outbound internal message.

`"allBalance"` - used to transfer all funds in the wallet. Use `false` for a simple transfer.

> **Note**: Due to a bug setting `allBalance` to `true` currently causes errors. Single-custodian multisig wallets may use `sendTransaction` method with flag `130` and value `0` instead:
```
tonos-cli message <multisig_address> sendTransaction '{"dest":"raw_address","value":0,"bounce":true,"flags":130,"payload":""}' --abi <MultisigWallet.abi.json> --sign <seed_or_keyfile> --lifetime 3600
```

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign keyfile.json`

`lifetime` – message lifetime in seconds. Once this time elapses, the message will not be accepted by the contract.

The TONOS-CLI utility displays encrypted message text and a QR code that contains the submitTransaction message.

Example:

```
$ tonos-cli message 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc submitTransaction '{"dest":"0:255a3ad9dfa8aa4f3481856aafc7d79f47d50205190bd56147138740e9b177f3","value":567000000,"bounce":true,"allBalance":false,"payload":""}' --abi SetcodeMultisigWallet.abi.json --sign k1.keys.json --lifetime 3600
Config: default
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: submitTransaction
  params: {"dest":"0:255a3ad9dfa8aa4f3481856aafc7d79f47d50205190bd56147138740e9b177f3","value":567000000,"bounce":true,"allBalance":false,"payload":""}
     abi: SetcodeMultisigWallet.abi.json
    keys: k1.keys.json
lifetime: 3600
  output: None
Generating external inbound message...

MessageId: 649e36ac7d656d1ce99f3e8b235074ff2483e115596a0233caacdf0c4ccf78a1
Expire at: Thu, 08 Jul 2021 16:32:45 +0300
Message: 7b226d7367223a7b226d6573736167655f6964223a2236343965333661633764363536643163653939663365386232333530373466663234383365313135353936613032333363616163646630633463636637386131222c226d657373616765223a227465366363674542424145413051414252596742534d553677767679593746624464704a365a5748706b4c7846304545726f4b4a36775165555369536633674d415148686d4733712f3553464e2f79317a703749337433586243796874586a51734b48763437654e657479504f6e46524b3939487a444c7974644754307a4e784a50314e3964544a4c444f6766496a2b556f57784c366571686d456e7551422f655a61324d326d32546539794234723636447a61364c34635258306f744a4b46566143417741414158714747793062594f622b66524d64677332414341574f41424b7448577a763146556e6d6b44437456666a36382b6a366f45436a495871734b4f4a77364230324c763567414141414141414141414141414141454f58643446414d4141413d3d222c22657870697265223a313632353735313136352c2261646472657373223a22303a61343632396436313764663933316438616438366564323466346361633364333231373838626130383235373431343466353832306632383934343933666263227d2c226d6574686f64223a227375626d69745472616e73616374696f6e227d

<Message QR code>
```

Copy the message text or scan the QR code and [broadcast](#411-broadcast-previously-generated-message) the message online.

## 4.9. Create transaction confirmation offline

Once one of the custodians creates a new transaction on the blockchain, it has to get the required number of confirmations from other custodians.

To create a confirmation message offline use the following command:
```
tonos-cli message <multisig_address> confirmTransaction '{"transactionId":"<id>"}' --abi <MultisigWallet.abi.json> --sign "<seed_or_keyfile>" --lifetime 600
```
`transactionId` – the ID of the transaction can be acquired from the custodian who created it, or by requesting the list of transactions awaiting confirmation from the multisignature wallet.

`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`<seed_or_keyfile>` - can either be the custodian seed phrase or the corresponding custodian key pair file. If seed phrase is used, enclose it in double quotes.

Example:

`--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

`--sign keyfile.json`

`lifetime` – message lifetime in seconds. Once this time elapses, the message will not be accepted by the contract.

The TONOS-CLI utility displays encrypted transaction text and a QR code that contains the `confirmTransaction` message.

Example:

```
$ tonos-cli message 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc confirmTransaction '{"transactionId":"6982528395137505473"}' --abi SetcodeMultisigWallet.abi.json --sign k3.keys.json --lifetime 600
Config: default
Input arguments:
 address: 0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc
  method: confirmTransaction
  params: {"transactionId":"6982528395137505473"}
     abi: SetcodeMultisigWallet.abi.json
    keys: k3.keys.json
lifetime: 600
  output: None
Generating external inbound message...

MessageId: 1751be3063638271c2590ede75d71bfaa48b0dc76180443f1158ffc3d178148d
Expire at: Thu, 08 Jul 2021 15:59:47 +0300
Message: 7b226d7367223a7b226d6573736167655f6964223a2231373531626533303633363338323731633235393065646537356437316266616134386230646337363138303434336631313538666663336431373831343864222c226d657373616765223a227465366363674542416745416f51414252596742534d553677767679593746624464704a365a5748706b4c7846304545726f4b4a36775165555369536633674d41514478394d2b686c7a4a523034444370564d6c586e775954466344495532424a304d51304966654971476f36712b6646526f717545664c326b792f6c766873667133707a77704c4463504a48566b663472412b6a6f5870676565396d622b717338645a63654b383748416d63554a61714c69617677684e472f5761343539585a31694a414141415871474b734b6f594f62327778716e514f3167357579556b6a2f597759413d3d222c22657870697265223a313632353734393138372c2261646472657373223a22303a61343632396436313764663933316438616438366564323466346361633364333231373838626130383235373431343466353832306632383934343933666263227d2c226d6574686f64223a22636f6e6669726d5472616e73616374696f6e227d

<QR code>
```

Copy the message text or scan the QR code and [broadcast](#411-broadcast-previously-generated-message) the message online.

## 4.10. Generate deploy message offline

If needed, signed deploy message can be generated without immediately broadcasting it to the blockchain. Generated message can be [broadcasted](#411-broadcast-previously-generated-message) later.

```bash
tonos-cli deploy_message [--raw] [--output <path_to_file>] [--sign <deploy_seed_or_keyfile>] [--wc <int8>] [--abi <contract.abi.json>] <contract.tvc> <params>
```

`--raw` - use to create raw message boc.

`--output <path_to_file>` - specify path to file where the raw message should be written to, instead of printing it to terminal.

`<deploy_seed_or_keyfile>` - can either be the seed phrase used to generate the deployment key pair file or the key pair file itself. If seed phrase is used, enclose it in double quotes.

Example:

- `--sign "flip uncover dish sense hazard smile gun mom vehicle chapter order enact"`

or

- `--sign deploy.keys.json`
- `--wc <int8>` ID of the workchain the wallet will be deployed to (`-1` for masterchain, `0` for basechain). By default this value is set to 0.

`<contract.abi.json>` - contract interface file.

`<contract.tvc>` - compiled smart contract file.

`<params>` - deploy command parameters, depend on the contract.

Example (saving to a file contract deployment message to the masterchain):

```bash
$ tonos-cli deploy_message --raw --output deploy.boc --sign key.json --wc -1 --abi SafeMultisigWallet.abi.json SafeMultisigWallet.tvc '{"owners":["0x88c541e9a1c173069c89bcbcc21fa2a073158c1bd21ca56b3eb264bba12d9340"],"reqConfirms":1}'
Config: /home/user/tonos-cli.conf.json
Input arguments:
     tvc: SafeMultisigWallet.tvc
  params: {"owners":["0x88c541e9a1c173069c89bcbcc21fa2a073158c1bd21ca56b3eb264bba12d9340"],"reqConfirms":1}
     abi: SafeMultisigWallet.abi.json
    keys: key.json
      wc: -1

MessageId: 51da1b8840bd12f9ef5152639bd1fe9062d77ed91829301043bb85b4a4d610ea
Expire at: unknown
Message saved to file deploy.boc
Contract's address: -1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6
Succeeded.
```

## 4.11. Broadcast previously generated message

Use the following command to broadcast any previously generated message (transaction message, confirmation message, deploy message):
```
tonos-cli send --abi <MultisigWallet.abi.json> "message"
```
`<MultisigWallet.abi.json>` - either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json` depending on the contract you have selected at step [2.2](#22-download-contract-files).

`message` – the content of the message generated by the TONOS-CLI utility during message creation. It should be enclosed in double quotes.

Example:

```bash
$ tonos-cli send --abi SafeMultisigWallet.abi.json "7b226d7367223a7b226d6573736167655f6964223a2266363364666332623030373065626264386365643265333865373832386630343837326465643036303735376665373430376534393037646266663338626261222c226d657373616765223a227465366363674542424145413051414252596742534d553677767679593746624464704a365a5748706b4c7846304545726f4b4a36775165555369536633674d41514868757856507a324c5376534e663344454a2f374866653165562f5a78324d644e6b4b727770323865397a7538376a4d6e7275374c48685965367642523141756c48784b44446e4e62344f47686768386e6b6b7a48386775456e7551422f655a61324d326d32546539794234723636447a61364c34635258306f744a4b465661434177414141586c4d464e7077594a61616b524d64677332414341574f663459757151715976325233654e776d49655834517048686e37537a75624c76524838657931425a6a617a6a414141414141414141414141414141414a4d61735142414d4141413d3d222c22657870697265223a313632303438323730352c2261646472657373223a22303a61343632396436313764663933316438616438366564323466346361633364333231373838626130383235373431343466353832306632383934343933666263227d2c226d6574686f64223a227375626d69745472616e73616374696f6e227d"
Config: /home/user/tonos-cli.conf.json
Input arguments:
 message: 7b226d7367223a7b226d6573736167655f6964223a2266363364666332623030373065626264386365643265333865373832386630343837326465643036303735376665373430376534393037646266663338626261222c226d657373616765223a227465366363674542424145413051414252596742534d553677767679593746624464704a365a5748706b4c7846304545726f4b4a36775165555369536633674d41514868757856507a324c5376534e663344454a2f374866653165562f5a78324d644e6b4b727770323865397a7538376a4d6e7275374c48685965367642523141756c48784b44446e4e62344f47686768386e6b6b7a48386775456e7551422f655a61324d326d32546539794234723636447a61364c34635258306f744a4b465661434177414141586c4d464e7077594a61616b524d64677332414341574f663459757151715976325233654e776d49655834517048686e37537a75624c76524838657931425a6a617a6a414141414141414141414141414141414a4d61735142414d4141413d3d222c22657870697265223a313632303438323730352c2261646472657373223a22303a61343632396436313764663933316438616438366564323466346361633364333231373838626130383235373431343466353832306632383934343933666263227d2c226d6574686f64223a227375626d69745472616e73616374696f6e227d
     abi: SafeMultisigWallet.abi.json
Connecting to net.ton.dev

MessageId: f63dfc2b0070ebbd8ced2e38e7828f04872ded060757fe7407e4907dbff38bba
Expire at: Sat, 08 May 2021 17:05:05 +0300
Calling method submitTransaction with parameters:
{
  "dest": "-1:0c5d5215317ec8eef1b84c43cbf08523c33f69677365de88fe3d96a0b31b59c6",
  "value": "1234000000",
  "bounce": false,
  "allBalance": false,
  "payload": "te6ccgEBAQEAAgAAAA=="
}
Processing... 
Processing... 
Succeded.
Result: {
  "transId": "6959904904053506881"
}
```

If transaction requires multiple confirmations, the terminal displays the transaction ID, which should be sent to other wallet custodians.

# 5. Error codes

Errors related to the operation of multisig contracts typically are displayed like this:

```bash
{
  "code": 507,
  "message": "Message expired. Contract was not executed on chain. Possible reason: Contract execution was terminated with error: Contract did not accept message, exit code: 103. For more information about exit code check the contract source code or ask the contract developer",
  "data": {
    "message_id": "029502efa1f4d5701713de772947de0c9447746abfb1c1191e403220698cf8cb",
    "shard_block_id": "baf38272f69eca4291e58958813d82cbc3e2107f0dc63ed261c2017232e3b714",
    "core_version": "1.14.1",
    "waiting_expiration_time": "Thu, 20 May 2021 18:23:37 +0300 (1621524217)",
    "block_time": "Thu, 20 May 2021 18:23:40 +0300 (1621524220)",
    "account_address": "0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc",
    "local_error": {
      "code": 414,
      "message": "Contract execution was terminated with error: Contract did not accept message, exit code: 103. For more information about exit code check the contract source code or ask the contract developer",
      "data": {
        "core_version": "1.14.1",
        "phase": "computeVm",
        "exit_code": 103,
        "exit_arg": "0",
        "account_address": "0:a4629d617df931d8ad86ed24f4cac3d321788ba082574144f5820f2894493fbc"
      }
    },
    "config_servers": [
      "net1.ton.dev",
      "net5.ton.dev"
    ],
    "query_url": "https://net5.ton.dev/graphql"
  }
}
Error: All attempts have failed
Error: 1
```

Multisig error codes, corresponding to the event that caused the error are specified in the `exit_code` parameter.

The list of possible exit codes and what they mean is as follows:

**100** - message sender is not a custodian - `sendTransaction`, `submitTransaction` or `confirmTransaction` method was called by someone who is not a wallet custodian.

**102** - transaction does not exist - ID of the transaction that custodian attempted to confirm is not present in multisig.

**103** - operation is already confirmed by this custodian - custodian attempted to confirm transaction twice.

**107** - input value is too low - transaction amount is less than the minimum amount (1000000 nanotons).

**108** - wallet should have only one custodian - wallet custodian attempted to call `sendTransaction` in a wallet with more than one custodian.

**113** - Too many requests for one custodian - the maximum amount of queued `submitTransaction` and `submitUpdate` calls was reached (currently, this amount is set to 5). Custodian has to wait until the calls are executed, before queuing any more.

**117** - invalid number of custodians - the number of custodians specified during multisig deploy exceeds the maximum amount (currently, this amount is set to 32).

**121** - payload size is too big; `submitTransaction` payload exceeds the maximum limit.

**SetcodeMultisig-specific errors**

**115** - update request does not exist - Setcode request with the specified ID is not present in the multisig.

**116** - update request already confirmed by this custodian - Setcode request with the specified ID is already confirmed by the current custodian.

**119** - stored code hash and calculated code hash are not equal - the code hash submitted in `executeUpdate` is not equal to the code previously submitted in `submitUpdate` .

**120** - update request is not confirmed; cannot perform `executeUpdate` as the setcode request was not confirmed by the required number of custodians yet.

**Currently unused error codes**

110 - too many custodians - not currently used.

122 - object is expired - not currently used.
