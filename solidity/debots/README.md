# DeBot smart contract readme

# Introduction

DeBot (Decentralized Bot) is an intuitive, chat-based user interface for smart contracts on TON Blockchain. DeBot interface consists of a DeBot browser, which has to support [DEngine](https://github.com/tonlabs/debot-engine) and DeBot smart contract, which acts as an intermediary between the user and the target smart contract the user wants to access.

This repository contains the following DeBot smart contracts: 

## Multisig DeBot

Multisig DeBot enables the user to work with any of the Multisig wallet contracts ([SafeMultisig](https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/safemultisig) or [SetcodeMultisig](https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/setcodemultisig)) in a chat-based interface.

It supports the following actions with a multisig wallet contract:

- wallet deployment
- checking wallet balance
- checking wallet custodian list
- checking pending transactions in the wallet
- making transactions
- confirming transactions

## Magister Ludi DeBot

Magister Ludi DeBot is a specialized DeBot created to help winners of the validator contest deploy their wallets to the FreeTON network.

It supports the following functions:

- checking public keys provided by the user against a list of contest winners
- configuring the wallet to be deployed
- verifying that all wallet custodian keys are in possession of the user
- deploying the configured SafeMultisig wallet

# How to use

When [compiling](https://docs.ton.dev/86757ecb2/v/0/p/950f8a-write-smart-contract-in-solidity/t/1620b2) DeBot smart contract, make sure to place the Debot.sol file into the folder with your DeBot contract code.

[Deploy](https://docs.ton.dev/86757ecb2/v/0/p/8080e6-tonos-cli/t/478a51) DeBot smart contract to the blockchain with at least 1 token balance.

## Multisig DeBot deployment
To deploy Multisig DeBot:

1. Download Multisig DeBot contract files from this repository (`msigDebot.tvc` and `msigDebot.abi.json`).
2. Download the ABI file of the target Multisig contract (either [SafeMultisigWallet.abi.json](https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/master/solidity/safemultisig/SafeMultisigWallet.abi.json) or [SetcodeMultisigWallet.abi.json](https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/master/solidity/setcodemultisig/SetcodeMultisigWallet.abi.json)).
3. Place all three files into a single folder.
4. Generate address and deployment keys for the DeBot contract:

    ```jsx
    tonos-cli genaddr msigDebot.tvc msigDebot.abi.json --genkey debot.keys.json
    ```

5. Transfer at least 1 token to the generated contract address.
6. Deploy and configure the Multisig DeBot contract. The best way to do it is with a single script. Here is an example of the script for Linux: 

    ```jsx
    smc_abi=$(cat <msig.abi.json> | xxd -ps -c 20000)
    debot_abi=$(cat msigDebot.abi.json | xxd -ps -c 20000)
    zero_address=0:0000000000000000000000000000000000000000000000000000000000000000
    ./tonos-cli deploy msigDebot.tvc "{\"options\":0,\"debotAbi\":\"\",\"targetAddr\":\"$zero_address\",\"targetAbi\":\"\"}" --sign debot.keys.json --abi msigDebot.abi.json
    ./tonos-cli call <debot_address> setABI "{\"dabi\":\"$debot_abi\"}" --sign debot.keys.json --abi msigDebot.abi.json
    ./tonos-cli call <debot_address> setTargetABI "{\"tabi\":\"$smc_abi\"}" --sign debot.keys.json --abi msigDebot.abi.json
    ```

    where

    `<msig.abi.json>` - ABI of the target contract (either `SafeMultisigWallet.abi.json` or `SetcodeMultisigWallet.abi.json`).

    `<debot_address>` - address of the DeBot contract, generated at step 4.

    `debot.keys.json` - the DeBot deployment keyfile generated at step 4.

    The script performs the following actions:

    - stores the content of the ABI files required for DeBot operation as variables
    - calls the DeBot constructor function leaving its options empty, or setting them to zero.
    - calls DeBot's `SetABI` and `setTargetABI` configuration functions, uploading the content of the necessary ABI files to it

    **Note**: Three separate functions are required in case of Multisig DeBot due to the large size of the contract and the ABI files. Combining all three into a single message would exceed message size limits of the blockchain.

    **Note**: There is no need to specify a valid `targetAddr` during deploy: Multisig DeBot asks the user for the target address at the beginning of each session. Zero address is used instead.
    
## Call DeBot

Call deployed DeBot in any DeBot browser.

**Example**: in [tonos-cli](https://github.com/tonlabs/tonos-cli) the DeBot can be called with the following command:

```
tonos-cli debot fetch <debot_address>
```
