This document contains instructions on how to deploy and configure a DePool smart contract.

# Prerequisites

TONOS-CLI of the latest version installed and configured [<link>](https://docs.ton.dev/86757ecb2/p/8080e6-tonos-cli).

# Procedure

To function correctly, the DePool contract requires a set of supporting smart contracts, that have to be deployed and configured alongside it:

1) The Validator Wallet, which should be a multisignature wallet with at least three custodians.

2) Two proxy smart contracts on the masterchain, which will pass messages from the DePool to the Elector smart contract. Two proxies are required to support two investment rounds running in parallel, one for odd rounds, and one for even rounds. 

3) The DePool contract itself.

4) The DePool Helper contract, which is connected to the global Timer contract and ensures regular operation of the DePool.

Once all of these contracts are deployed and configured, the DePool is ready to receive stakes.

Follow the steps described below to complete this procedure.

## 1. Set Up Node and Deploy Validator Wallet

When using DePool you may set up the validator wallet on the basechain, as the DePool itself operates on the basechain and will pass your stakes to the masterchain Elector contract through its proxy contracts.

With that in mind, follow this procedure up to step 4.4 (the validator script in step 5 will be different) and make sure to set up at least three custodians for your wallet:

[https://docs.ton.dev/86757ecb2/p/708260-run-validator/t/08f3ce](https://docs.ton.dev/86757ecb2/p/708260-run-validator/t/08f3ce)

Save the wallet address. It will be needed on the following steps.

As always, also make sure to securely backup all of your seed phrases and/or wallet keys, generated during wallet and node setup. If you lose them, you will not be able to recover access to your funds.

**Note**: If you mean to participate in the DePool Contest, make sure to communicate your multisig address to the contest admins, as soon as you have generated it. They will send you the coins required to initialize the wallet.

**Also note**, that the validator wallet should have a small sum of tokens available at all times to reliably send election requests to DePool. Each election request costs ~ 1 Ton.

## 2. Prepare DePool and Supporting Smart Contracts

Obtain contract code from the repository.

The files required for DePool deployment are comprised of three pairs of compiled contract .tvc files and their corresponding ABI files:

`DePoolProxy.tvc` and `DePoolProxy.abi.json`

`DePool.tvc` and `DePool.abi.json`

`DePoolHelper.tvc` and `DePoolHelper.abi.json`

## 3. Generate Deployment Keys

Use TONOS-CLI to generate four different seed phrases for the four contracts you will be deploying:

```bash
tonos-cli genphrase
```

Do not reuse wallet keys, or any other keys you may have used elsewhere already.

Securely backup these seed phrases and keep them secret, as without them, control over the DePool contract will be lost. If you suspect that your keys are compromised, close the DePool and deploy it anew with new keys and a new set of supporting contracts.

Generate key pair files from the four seed phrases (this step is intended for the sake of convenience as nothing in the seed phrases indicates for what contract they are intended, and they are easy to mix up).

```bash
tonos-cli getkeypair proxy0.json "seed_phrase_for_proxy0"
tonos-cli getkeypair proxy1.json "seed_phrase_for_proxy1"
tonos-cli getkeypair depool.json "seed_phrase_for_depool"
tonos-cli getkeypair helper.json "seed_phrase_for_helper"
```

## 4. Calculate Contract Addresses

The smart contracts you will be deploying need to be configured to know the addresses of each other. Thus, first you have to calculate and save the addresses of every contract to be deployed.

### 4.1. Calculate addresses for both proxies on the masterchain

The proxies have to be located on the masterchain to successfully pass the stakes from the DePool, which is located on the basechain to the masterchain Elector contract, which does not accept messages from the basechain by design.

```bash
tonos-cli genaddr DePoolProxy.tvc DePoolProxy.abi.json --setkey proxy0.json --wc -1
tonos-cli genaddr DePoolProxy.tvc DePoolProxy.abi.json --setkey proxy1.json --wc -1
```

Save both proxy addresses. 

### 4.2. Calculate DePool address

```bash
tonos-cli genaddr DePool.tvc DePool.abi.json --setkey depool.json
```

Save the DePool address.

Put it into `~/ton-keys/depool.addr` file in your validator node setup.

**Note**: When participating the DePool contest, this address should also be promptly communicated to the contest admins.

### 4.3. Calculate DePool Helper address

```bash
tonos-cli genaddr DePoolHelper.tvc DePoolHelper.abi.json --setkey helper.json
```

Save the DePool Helper address.

## 5. Send Coins to the Calculated Addresses

Send some coins to all four addresses calculated on step 4 to initialize them with the following command:

```bash
tonos-cli call <wallet_address> submitTransaction '{"dest":"contract_address","value":*number*,"bounce":"false","allBalance":"false","payload":""}' --abi <MultisigWallet.abi.json> --sign <wallet_seed_or_keyfile>
```

where

`<wallet_address>` - is the address of the wallet, from which you are making the transaction

`contract_address` - address of one of the contracts, calculated on step 4.

`"value":*number*` - the amount of coins to be transferred (in nanotokens).

`"bounce":"false"` - bounce flag set to false, to allow a transaction to an account that is not yet initialized.

`<MultisigWallet.abi.json>` - the ABI file of the contract, from which you are making the transaction (for validator wallets -  usually `SafeMultisigWallet.abi.json`)

`<wallet_seed_or_keyfile>` - either the seed phrase in double quotes, or the path to the keyfile for the wallet, from which you are making the transaction

`allBalance` and `payload` values in this case remain default.

Example:

```bash
tonos-cli call 0:2bb4a0e8391e7ea8877f4825064924bd41ce110fce97e939d3323999e1efbb13 submitTransaction '{"dest":"0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace","value":200000000,"bounce":"false","allBalance":"false","payload":""}' --abi ./SafeMultisigWallet.abi.json --sign ./wallet.json
```

Confirm the transaction, if it is required: [https://docs.ton.dev/86757ecb2/p/94921e-multisignature-wallet-management-in-tonos-cli/t/61177b](https://docs.ton.dev/86757ecb2/p/94921e-multisignature-wallet-management-in-tonos-cli/t/61177b)

Such a transaction should be repeated for every address calculated on step 4: two proxy contracts on the masterchain, the DePool contract itself, and the DePool Helper contract (**there should be a total of four such transactions**).

## 6. Deploy Contracts

### 6.1. Deploy Proxy contracts to the masterchain

The proxies have to be located on the masterchain to successfully pass the stakes from the DePool, which is located on the basechain to the masterchain Elector contract, which does not accept messages from the basechain by design.

Use the following commands to deploy the proxies:

```bash
tonos-cli deploy DePoolProxy.tvc '{"depool":"DePoolAddress"}' --abi DePoolProxy.abi.json --sign proxy0.json --wc -1
tonos-cli deploy DePoolProxy.tvc '{"depool":"DePoolAddress"}' --abi DePoolProxy.abi.json --sign proxy1.json --wc -1
```

Where 

`DePoolAddress` – address of the DePool contract from step 4.2.

Example:

```bash
tonos-cli deploy DePoolProxy.tvc '{"depool":"0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace"}' --abi DePoolProxy.abi.json --sign proxy0.json --wc -1
```

**Note**: The only difference between the commands for the two proxies is the keyfile with which they are signed. It ensures that each proxy is deployed to its own correct address.

### 6.2. Deploy DePool contract to the basechain

```bash
tonos-cli deploy DePool.tvc '{"minRoundStake":*number*,"proxy0":"proxy0Address","proxy1":"proxy1Address","validatorWallet":"validatorWalletAddress","minStake":*number*}' --abi DePool.abi.json --sign depool.json
```

Where 

`"minRoundStake":*number*` – minimal total stake (in nanotons) that has to be accumulated in the DePool to participate in elections. Should be chosen based on the current validator stakes in the network, so that the your DePool can successfully compete in the elections. For participants of the DePool Contest, this value should be no more than half of the stake given to them for the contest.

`proxy0Address` – address of the first proxy from step 4.1

`proxy1Address` – address of the second proxy from step 4.1

`validatorWalletAddress` – validator wallet address from step 1

`"minStake":*number*` – minimum stake (in nanotons) that DePool accepts from participants. It's recommended to set it not less than 10 Tons.

Example:

```bash
tonos-cli deploy DePool.tvc '{"minRoundStake":100000000000000,"proxy0":"-1:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3","proxy1":"-1:c63a050fe333fac24750e90e4c6056c477a2526f6217b5b519853c30495882c9","validatorWallet":"0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e","minStake":50000000000}' --abi DePool.abi.json --sign depool.json
```

### 6.3. Deploy DePool Helper contract to the basechain

```bash
tonos-cli deploy DePoolHelper.tvc '{"pool":"DePoolAddress"}' --abi DePoolHelper.abi.json --sign helper.json
```

Where 

`DePoolAddress` – address of the DePool contract from step 4.2.

Example:

```bash
tonos-cli deploy DePoolHelper.tvc '{"pool":"0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace"}' --abi DePoolHelper.abi.json --sign helper.json
```

## 7. Configure DePool Helper Contract

DePool Helper contract needs to be connected to the global Timer contract. Use the following command:

```bash
tonos-cli call HelperAddress initTimer '{"timer":"TimerAddress","period":*number*}' --abi DePoolHelper.abi.json --sign helper.json
```

where

`HelperAddress` – is the address of the Helper contract from step 4.3

`TimerAddress` - is the address of the global timer contract.

`"period":*number*` - is the period for regular DePool contract calls via ticktock messages (in
seconds). This period should be chosen based on the duration of the validation cycle on the blockchain. At a minimum DePool Helper contract should be set to call the DePool contract once every step of the validation cycle.

Example:

```bash
tonos-cli call 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e initTimer '{"timer":"0:c63a050fe333fac24750e90e4c6056c477a2526f6217b5b519853c30495882c9","period":3600}' --abi DePoolHelper.abi.json --sign helper.json
```

**Note**: Timer contract and period may be changed at any time with this command.

## 8. Make Stakes

**Note**: The participants of the DePool contest will have a lock stake sufficient to participate in the contest made for them for its full duration.

TONOS-CLI permits to manage several types of stakes. For details on stake types refer to the [DePool specifications](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications).

To participate in elections, DePool has to accumulate, through stakes from the validator wallet and, optionally, from other wallets, a staking pool, the total of which exceeds `minRoundStake`, and validator's share of which is not less than 0.2 * `minRoundStake`(see section 6.2 [above](https://docs.ton.dev/86757ecb2/v/0/p/37a848-run-depool/t/72e578)).

Below are listed the commands used to manage stakes.

### Deposit stakes

For all commands listed below, the DePool address, the wallet making the stake, and the path to the keyfile/seed phrase may be specified in the TONOS-CLI config file in advance:

```bash
tonos-cli config --addr <address> --wallet <address> --keys <path_to_keys or seed_phrase>
```

Where

`--addr <address>` - the address of the DePool

`--wallet <address>` - the address of the wallet making the stake

`path_to_keys or seed_phrase` -  either the keyfile for the wallet making the stake, or the seed phrase in quotes.

In this case all commands allow to omit `--addr`, `--wallet` and `--sign` options.

Example:

```bash
tonos-cli config --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --keys "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### 1) Ordinary stake

Ordinary stake is the most basic type of stake. It and the rewards from it belong to the wallet that made it.

```bash
tonos-cli depool [--addr <depool_address>] stake ordinary [--wallet <msig_address>] --value <number> [--autoresume-off] [--sign <key_file or seed_phrase>]
```

Where

`depool_address` - address of the DePool contract.

`msig_address` - address of the wallet making a stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`--autoresume-off` - participant stake will not be automatically reinvested to the next round.

`key_file or seed_phrase` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake ordinary --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 100.5 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### 2) Vesting stake

Any wallet can make a vesting stake into round and define a target participant address (beneficiary) who will own this stake. But not the whole stake is available to the beneficiary at once. Instead it is split into parts and the next part of stake becomes available to the beneficiary only when next withdrawal period is ended. Rewards from vesting stake are available to the beneficiary at any time. Please note that the vesting stake is split into two equal parts by the DePool, to be used in both odd and even rounds, so to ensure DePool can participate in elections with just one vesting stake where validator wallet is beneficiary, that stake should equal  `minRoundStake *2`.

```bash
tonos-cli depool [--addr <depool_address>] stake vesting [--wallet <msig_address>] --value <number> --total <days> --withdrawal <days> --beneficiary <address> [--sign <key_file or seed_phrase>]
```

Where

`depool_address` - address of the DePool contract.

`msig_address` - address of the wallet making a stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`total <days>` - total period, for which the stake is made. 0 <`total`< 18 years.

`withdrawal <days>` - withdrawal period (each time a withdrawal period ends, a portion of the stake is released to the beneficiary). Total period should be exactly divisible by withdrawal period.

`beneficiary <address>` - address of the wallet that will receive rewards from the stake and, in parts over time, the vesting stake itself.

`key_file or seed_phrase` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake vesting --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 1000 --total 360 --withdrawal 30 --beneficiary 0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### 3) Lock stake

Any wallet can make a lock stake, in which it locks its funds in DePool for a defined period, but rewards from this stake will be payed to another target participant (beneficiary). At the end of a period the Lock Stake should be returned to the wallet which locked it. Please note that the lock stake is split into two equal parts by the DePool, to be used in both odd and even rounds, so to ensure DePool can participate in elections with just one lock stake where validator wallet is beneficiary, the stake should equal   `minRoundStake *2`.

**Note**: This is the type of stake that will be made for all DePool contest participants.

```bash
tonos-cli depool [--addr <depool_address>] stake lock [--wallet <msig_address>] --value <number> --total <days> --withdrawal <days> --beneficiary <address> [--sign <key_file or seed_phrase>]
```

Where

`depool_address` - address of the DePool contract.

`msig_address` - address of the wallet making a stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`total <days>` - total period, for which the stake is made. 0 <`total`< 18 years.

`withdrawal <days>` - withdrawal period (each time a withdrawal period ends, a portion of the stake is returned to the wallet that made the stake). Total period should be exactly divisible by withdrawal period.

`beneficiary <address>` - address of the wallet that will receive rewards from the stake.

`key_file or seed_phrase` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake lock --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 1000 --total 360 --withdrawal 30 --beneficiary 0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### Remove stakes

This command removes an ordinary stake from a pooling round (while it has not been staked in the Elector yet):

```bash
tonos-cli depool [--addr <depool_address>] stake remove [--wallet <msig_address>] --value <number> [--sign <key_file or seed_phrase>]
```

Where

`depool_address` - address of the DePool contract.

`msig_address` - address of the wallet that made the stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`key_file or seed_phrase` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake remove --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 100 --from-round 1 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### Transfer stakes

The following command assigns an existing ordinary stake or its part to another participant wallet. If the entirety of the stake is transferred, the transferring wallet is removed from the list of participants n the DePool. If the receiving wallet isn't listed among the participants, it will become a participant as the result of the command.

```bash
tonos-cli depool [--addr <depool_address>] stake transfer [--wallet <msig_address>] --value <number> --dest <address> [--sign <key_file or seed_phrase>]
```

Where

`depool_address` - address of the DePool contract.

`msig_address` - address of the wallet that made the stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`dest <address>` - address of the new owner of the stake.

`key_file or seed_phrase` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake transfer --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 1000 --dest 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### Withdraw Stakes

The following command allows to withdraw an ordinary stake to the wallet that owns it. Use `withdraw on` to receive the stake, as soon as it becomes available. If you then make another stake, and want to keep reinvesting it every round, run the command with `withdraw off`.

```bash
tonos-cli depool [--addr <depool_address>] withdraw on | off [--wallet <msig_address>] [--sign <key_file or seed_phrase>]
```

Where

`depool_address` - address of the DePool contract.

`msig_address` - address of the wallet that made the stake.

`key_file or seed_phrase` - either the keyfile for the wallet that made the stake, or the seed phrase in quotes.

## 9. Check Stakes in the DePool

After the stake is made, you can check its status in the DePool with the `getParticipantInfo` get-method:

```bash
tonos-cli run <depool_address> getParticipantInfo '{"addr":"<msig_address>"}' --abi DePool.abi.json
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet that made the stake.
