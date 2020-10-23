# DeBot smart contract readme

# Introduction

DeBot (Decentralized Bot) is an intuitive, chat-based user interface for smart
contracts on TON Blockchain. DeBot interface consists of a DeBot browser, which has to support [DEngine](https://github.com/tonlabs/debot-engine) and DeBot smart contract, which acts as an intermediary between the user and the target smart contract they user wants to access.

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

1. When [compiling](https://docs.ton.dev/86757ecb2/v/0/p/950f8a-write-smart-contract-in-solidity/t/1620b2) DeBot smart contract, make sure to place the Debot.sol file into the folder with your DeBot contract code.
2. [Deploy](https://docs.ton.dev/86757ecb2/v/0/p/8080e6-tonos-cli/t/478a51) DeBot smart contract to the blockchain with at least 1 token balance.
3. Call DeBot in any DeBot browser.

    **Example**: in [tonos-cli](https://github.com/tonlabs/tonos-cli) the DeBot can be called with the following command:

    ```jsx
    tonos-cli debot fetch <debot_address>
    ```
