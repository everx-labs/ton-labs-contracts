# DePool

This document contains instructions on how to deploy and configure a DePool smart contract, and run a validator node through it. For detailed information on DePool specifications, please refer to the [relevant document](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications).

It is intended for the DePool v2 dated December 11, 2020. For instructions on the previous version of DePool see [this document](https://docs.ton.dev/86757ecb2/v/0/p/37a848-run-depool).

Answers to frequently asked questions can be found [here](https://docs.ton.dev/86757ecb2/p/45fa44-depool-faq).

> Note: One node can be assigned to only one DePool contract.

> Note: Validator contest winners are strongly recommended not to deploy DePool to the main net without previously testing it out on the devnet for a few days. The time for DePool deployment will be announced additionally. Test tokens for staking on the devnet can be requested from community admins.

# Prerequisites

[TONOS-CLI](https://docs.ton.dev/86757ecb2/p/8080e6-tonos-cli) of the latest version (0.1.25 and higher) installed and configured.

[tvm_linker](https://github.com/tonlabs/TVM-linker) utility.

[Resources](https://docs.ton.dev/86757ecb2/v/0/p/708260-run-validator/t/2177a7) required to run a node available.

# Procedure

To function correctly, the DePool contract requires an active validator node and a set of supporting smart contracts, that have to be deployed and configured alongside it:

1. The Validator Wallet, which should be a [multisignature wallet](https://docs.ton.dev/86757ecb2/v/0/p/94921e-multisignature-wallet-management-in-tonos-cli/t/97ee3f) with at least three custodians and `reqConfirms` > 1. **Can be deployed to the basechain**. **For Validator contest winners on the main net this has to be the wallet deployed through Magister Ludi DeBot.**
2. The DePool contract itself, **deployed to the basechain**. DePool contract deploys two proxy smart contracts to the masterchain, which will pass messages from the DePool to the Elector smart contract. Two proxies are required to support two staking rounds running in parallel, one for odd rounds, and one for even rounds.
3. Optionally, the DePool Helper contract, which is connected to the global Timer contract and ensures regular operation of the DePool. Also **deployed to the basechain.** Can be replaced with other methods of updating DePool state.

> Important: the only contracts requiring masterchain in this setup are the two proxy contracts, **which are deployed by DePool**. Everything else is designed to function on the basechain, as the contracts are rather complex and consume a lot of gas.

Once all of these contracts are deployed and configured, the DePool is ready to receive stakes.

Follow the steps described below to complete this procedure.

## 1. Set Up Node and Deploy Validator Wallet

When using DePool you may set up the validator wallet **on the basechain**, as the DePool itself operates on the basechain and will pass your stakes to the masterchain Elector contract through its proxy contracts.

With that in mind, follow [this procedure](https://docs.ton.dev/86757ecb2/p/708260-run-validator/t/08f3ce) **up to step 4.4** (the validator script in step 5 will be different) and make sure to set up at least three custodians for your wallet.

> **Note**: **For Validator contest winners on the main net this wallet has to be deployed through Magister Ludi DeBot.**

Make sure that in the course of the procedure:

1. validator wallet address was specified in the `~/ton-keys/$(hostname -s).addr` file.
2. validator wallet keys were saved to the `~/ton-keys/msig.keys.json` file.

The wallet address will also be needed on the following steps.

As always, also make sure to securely backup all of your seed phrases and/or wallet keys, generated during wallet and node setup. If you lose them, you will not be able to recover access to your funds.

> Note:  The validator wallet should have a small sum of tokens available at all times to reliably send election requests to DePool. Each election request costs ~ 1 Ton.

## 2. Prepare DePool and Supporting Smart Contracts

Obtain contract code from the [repository](https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/depool).

The files required for DePool deployment are comprised of three pairs of compiled contract .tvc files and their corresponding ABI files:

`DePoolProxy.tvc`

`DePool.tvc` and `DePool.abi.json`

`DePoolHelper.tvc` and `DePoolHelper.abi.json`

## 3. Generate Deployment Keys

Use TONOS-CLI to generate seed phrases for the contracts you will be deploying:

```bash
tonos-cli genphrase
```

Do not reuse wallet keys, or any other keys you may have used elsewhere already.

Securely backup these seed phrases and keep them secret, as without them, control over the DePool contract will be lost (for example, without its key, the DePool cannot be closed). If you suspect that your keys are compromised, close the DePool and deploy it anew with new keys and a new set of supporting contracts.

Generate key pair files from the seed phrases (this step is intended for the sake of convenience as nothing in the seed phrases indicates for what contract they are intended, and they are easy to mix up).

```bash
tonos-cli getkeypair depool.json "seed_phrase_for_depool"
tonos-cli getkeypair helper.json "seed_phrase_for_helper"
```

## 4. Calculate Contract Addresses

The smart contracts you will be deploying need to be configured to know the addresses of each other. Thus, first you have to calculate and save the addresses of every contract to be deployed.

### 4.1. Calculate DePool address

```bash
tonos-cli genaddr DePool.tvc DePool.abi.json --setkey depool.json
```

Save the DePool address.

Put it into `~/ton-keys/depool.addr` file in your validator node setup. It will be required for the validator script.

### 4.2. (Optional) Calculate DePool Helper address

```bash
tonos-cli genaddr DePoolHelper.tvc DePoolHelper.abi.json --setkey helper.json
```

Save the DePool Helper address.

## 5. Send Coins to the Calculated Addresses

Send some coins to all addresses calculated on step 4 to initialize them with the following command:

```bash
tonos-cli call <wallet_address> submitTransaction '{"dest":"contract_address","value":*number*,"bounce":"false","allBalance":"false","payload":""}' --abi <MultisigWallet.abi.json> --sign <wallet_seed_or_keyfile>
```

Where

`<wallet_address>` - is the address of the wallet, from which you are making the transaction

`<contract_address>` - address of one of the contracts, calculated on step 4.

`"value":*number*` - the amount of coins to be transferred (in nanotokens).

`"bounce":"false"` - bounce flag set to false, to allow a transaction to an account that is not yet initialized.

`<MultisigWallet.abi.json>` - the ABI file of the contract, from which you are making the transaction (for validator wallets - usually `SafeMultisigWallet.abi.json`)

`<wallet_seed_or_keyfile>` - either the seed phrase in double quotes, or the path to the keyfile for the wallet, from which you are making the transaction

`allBalance` and `payload` values in this case remain default.

Example:

```bash
tonos-cli call 0:2bb4a0e8391e7ea8877f4825064924bd41ce110fce97e939d3323999e1efbb13 submitTransaction '{"dest":"0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace","value":200000000,"bounce":"false","allBalance":"false","payload":""}' --abi ./SafeMultisigWallet.abi.json --sign ./wallet.json
```

[Confirm the transaction](https://docs.ton.dev/86757ecb2/p/94921e-multisignature-wallet-management-in-tonos-cli/t/61177b), if it is required.

Such a transaction should be repeated for every address calculated on step 4: the DePool contract itself and, optionally, the DePool Helper contract.

The recommended initial amounts are:

- 20 Tons to the DePool conrtact
- 5 Tons to the DePool Helper
- 10 Tons should be left on the validator wallet

For the duration of the DePool existence, balance on all DePool-related contracts should be maintained:

> Proxies receive fees for their services automatically, but if they run out of funds for any reason, DePool might miss elections.

> Helper, on the other hand, should be topped up regularly, depending on the set timer period. Without funds on the Helper contract, DePool will not be able to function regularly.

> The DePool itself receives funds for its operations from validation rewards, but may also, if it stops receiving these rewards, run out of funds.

## 6. Deploy Contracts

### 6.1. Deploy DePool contract to the basechain

```bash
tonos-cli deploy DePool.tvc '{"minStake":*number*,"validatorAssurance":*number*,"proxyCode":"ProxyContractCodeInBase64","validatorWallet":"validatorWalletAddress","participantRewardFraction":*number*}' --abi DePool.abi.json --sign depool.json
```

 Where

`"minStake":*number*` – minimum stake (in nanotons) that DePool accepts from participants. It's recommended to set it not less than 10 tokens.

`"validatorAssurance":*number*` - minimal stake for validator. If validator has stake less than **validatorAssurance**, DePool won't be taking part in elections. ****

`ProxyContractCodeInBase64` - code of the proxy contract. Can be obtained by calling [tvm_linker](https://github.com/tonlabs/TVM-linker): 

```json
tvm_linker decode --tvc DePoolProxy.tvc
```

`<validatorWalletAddress>` – validator wallet address from step 1.

`"participantRewardFraction":*number*` - percentage of the total DePool reward (in integers, up to 99 inclusive) that goes to Participants. It's recommended to set it at 95% or more.

> **Important: You will not be able to change all of these parameters, except `participantRewardFraction`, after the DePool is deployed. They will influence the appeal of your DePool to potential participants:**

> `participantRewardFraction` determines what percentage of their total reward all participants will receive (too small, and other DePools might draw them away, too big, and your validator wallet might not receive enough rewards, to support validation and staking); it can be adjusted at any time by the DePool owner, but only upwards - see how in section 13. 

> `validatorAssurance` determines how much you take it upon yourself to invest in the DePool and lose in case of any validator node malfunction or misbehavior. If set too small, potential participants might decide you aren't risking enough and avoid your DePool in favor of others.

Example:

```bash
tonos-cli deploy DePool.tvc '{"minStake":10000000000,"validatorAssurance":100000000000000,"proxyCode":"te6ccgECHgEABV4AAib/APSkICLAAZL0oOGK7VNYMPShBwEBCvSkIPShAgIDzkAEAwAp32omhp/+mf6YB8NT/8MPwzfDH8MUAgFYBgUALV+ELIy//4Q88LP/hGzwsA+EoBzsntVIAMNfhBbpLwCN5opvxgINMf0z8zIYIQ/////rqOQXBopvtglWim/mAx34IQBV1KgKG1f/hKyM+FiM4B+gKNBEAAAAAAAAAAAAAAAAABD2mXdM8WIc8LP/hJzxbJcfsA3l8D8AeAIBIBEIAgFuEAkCASAPCgIBIA4LAYj6f40IYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABPhpIe1E0CDXScIBjhHT/9M/0wD4an/4Yfhm+GP4YgwB/o4+9AWNCGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAT4anABgED0DvK91wv/+GJw+GNw+GZ/+GHi0wABn4ECANcYIPkBWPhC+RDyqN7TPwGOHvhDIbkgnzAg+COBA+iogggbd0Cgud6S+GPggDTyNNjTHyHBAyINADaCEP////28sZZbcfAB8AXgAfAB+EdukzDwBd4Aq7S3uZJ8ILdJeARvaZ/ouDRTfbBKtFN/MBjvwQgCrqVAUNq//CVkZ8LEZwD9AUaCIAAAAAAAAAAAAAAAAAHz7QcaZ4sQ54Wf/CTni2S4/YAYeAO//DPAALe23RITPhBbpLwCN7TP9Mf0XBopvtglWim/mAx34IQBV1KgKG1f/hKyM+FiM4B+gKNBEAAAAAAAAAAAAAAAAABM+vBdM8WIs8LPyHPCx/4Sc8WyXH7AFvwB3/4Z4AC3uc3oqZ8ILdJeARvaZ/pj+i4NFN9sEq0U38wGO/BCAKupUBQ2r/8JWRnwsRnAP0BRoIgAAAAAAAAAAAAAAAAATtkCyZnixFnhZ+Q54WP/CTni2S4/YAt+AO//DPACASAXEgIBIBUTAem6i1Xz/4QW6OXO1E0CDXScIBjhHT/9M/0wD4an/4Yfhm+GP4Yo4+9AWNCGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAT4anABgED0DvK91wv/+GJw+GNw+GZ/+GHi3vhG8nNx+GbRcHCTIMECgUAFqOHcgg+EnPFiLPCwcxIMn5AFMzlTD4QiG63zRbpLUH6DDy4Gb4Sfhq8Ad/+GcBCbtbCzZYFgD6+EFukvAI3tM/+kDR+En4SscF8uBmcGim+2CVaKb+YDHfghAFXUqAobV/+CdvECGCEDuaygCgvvLgZ3BopvtglWim/mAx34IQBV1KgKG1fyLIz4WIzgH6Ao0EQAAAAAAAAAAAAAAAAAI7K6EkzxYjzws/yXH7AF8D8Ad/+GcCASAZGACfutvEKe+EFukvAI3tH4SoIQO5rKACLA/44tJNDTAfpAMDHIz4cgzo0EAAAAAAAAAAAAAAAACtvEKejPFiLPFiHPCz/JcfsA3luS8Afef/hngCASAdGgEJuHF1kZAbAfz4QW6S8Aje0z/T/9Mf0x/XDf+V1NHQ0//fINdLwAEBwACwk9TR0N7U+kGV1NHQ+kDf0fhJ+ErHBfLgZnBopvtglWim/mAx34IQBV1KgKG1f/gnbxAhghA7msoAoL7y4GdwaKb7YJVopv5gMd+CEAVdSoChtX8iyM+FiM4B+gIcAGCAas9Az4PIz5E5zdEuKc8LPyjPC/8nzwsfJs8LHyXPC/8kzxTNyXH7AF8I8Ad/+GcAgtxwItDTA/pAMPhpqTgA3CHHACCcMCHTHyHAACCSbCHe39whwQMighD////9vLGWW3HwAfAF4AHwAfhHbpMw8AXe","validatorWallet":"0:0123012301230123012301230123012301230123012301230123012301230123","participantRewardFraction":95}' --abi DePool.abi.json --sign depool.json --wc 0
```

At the time of deployment, the variable `m_balanceThreshold` is set as current DePool account balance - 5 tokens. DePool will replenish its balance from validation rewards to this value every round it receives rewards.

### 6.2. (Optional) Deploy DePool Helper contract to the basechain

```bash
tonos-cli deploy DePoolHelper.tvc '{"pool":"DePoolAddress"}' --abi DePoolHelper.abi.json --sign helper.json
```

Where

`<DePoolAddress>` – address of the DePool contract from step 4.1.

Example:

```bash
tonos-cli deploy DePoolHelper.tvc '{"pool":"0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace"}' --abi DePoolHelper.abi.json --sign helper.json
```

## 7. Configure DePool State Update method

There are three different methods of setting up regular state updates of the DePool contract available. You have to set up one of them to run regularly. The period for state updates should be chosen based on the duration of the validation cycle on the blockchain. At the very minimum DePool's state update function should be called three times during the validation cycle:

- Once after the elections begin, so DePool gets ready to receive and forward validator's election request.
- Once after the validation begins, to find out if it won elections or not.
- Once after unfreeze, to process stakes and rewards and rotate the rounds.

In the current network configuration, 1 and 3 coincide, so DePool's state update can be called twice during the validation cycle - once during elections and once during validation.

### State update through Multisig Contract

A Multisig wallet can be used instead of Helper to call DePool's ticktock function directly.

```bash
tonos-cli depool [--addr <depool_address>] ticktock [-w <msig_address>] [-s <path_to_keys_or_seed_phrase>]
```

Where

`--addr <depool_address>` - the address of the DePool

`-w <msig_address>` - the address of the multisig wallet used to call DePool

`-s <path_to_keys_or_seed_phrase>` - either the keyfile for the wallet, or the seed phrase in quotes

All these options can be skipped, if they were previously specified in the TONOS-CLI configuration file:

```bash
tonos-cli config --addr <address> --wallet <address> --keys <path_to_keys or seed_phrase>
```

1 token is always attached to this call. Change will be returned.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace ticktock -w 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e -s "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### State update through DePool Helper contract (temporarily unavailable)

If you have previously deployed DePool helper, you can set it up to regularly call the DePool state update ticktock function. To do it, DePool Helper contract needs to be connected to the global Timer contract. Use the following command:

```bash
tonos-cli call HelperAddress initTimer '{"timer":"TimerAddress","period":*number*}' --abi DePoolHelper.abi.json --sign helper.json
```

Where

`<HelperAddress>` – is the address of the Helper contract from step 4.2

`<TimerAddress>` - is the address of the global timer contract.

`"period":*number*` - is the period for regular DePool contract calls via ticktock messages (in seconds). This period should be chosen based on the duration of the validation cycle on the blockchain. At a minimum DePool Helper contract should be set to call the DePool contract once every step of the validation cycle.

Example:

```bash
tonos-cli call 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e initTimer '{"timer":"0:3a10ef5d6435e82eb243b41e620f6a7737a70694884aca1c52c99088efb7643d","period":3600}' --abi DePoolHelper.abi.json --sign helper.json
```

Timer contract and period may be changed at any time with this command.

**Timer fees**

Timer charges a fee for its services every time the Helper calls it.

The fees (in nanotons) are calculated according to the following formula:

`fee = period * timerRate + fwdFee * 8 + epsilon`

Where

`timerRate` = 400000 nanotons per second

`fwdFee` = 1000000 nanotons

`epsilon` = 1e9 nanotons

`period` = the period set in the DePool Helper contract (in seconds).

Thus, the longer the period set in the DePool Helper contract is, the higher a single timer fee will be.

To pay these fees reliably, sufficient positive balance (~100 Tons if the period is set to 1 hour) has to be maintained on the Helper. Without funds on the Helper contract, DePool will not be able to function regularly.

### State update through external call of the DePool Helper Contract

DePool Helper can be called to send the ticktock message manually at any time with the following command:

```bash
tonos-cli call <HelperAddress> sendTicktock {} --abi DePoolHelper.abi.json --sign helper.json
```

Where

`<HelperAddress>` – is the address of the Helper contract from step 4.2.

If needed, it can be set up to run regularly (for example, with `cron` utility) to supplement or replace the timer.

Example:

```bash
@hourly        cd <tonos-cli-dir> && tonos-cli call <HelperAddress> sendTicktock {} --abi DePoolHelper.abi.json --sign helper.json
```

Where

`<tonos-cli-dir>` - directory with TONOS-CLI configuration file, `DePoolHelper.abi.json` file and `helper.json` keyfile containing DePool Helper keys.

`<HelperAddress>` – is the address of the Helper contract from step 4.2.

## 8. Make Stakes

DePool collects stakes from various participants to be pooled together and forwarded as one stake to the Elector on behalf of its validator node.

Collection is continuous. Stakes can be made at any time, and will be distributed to whichever round is currently in the [pooling](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications/t/13b9d0) stage. Every time an election begins on the blockchain, the accumulated pool is locked and (if all conditions are met) staked in this election, and the pooling stage of the next round begins.

> Note: This means, that a DePool stake for a specific election needs to be made before the election begins.

To participate in elections, DePool has to accumulate, through stakes belonging to the validator wallet and, optionally, from other wallets, a staking pool, validator's share of which is not less than `validatorAssurance` (see section 6.1 above).

TONOS-CLI allows to manage several types of stakes. For details on stake types refer to the [DePool specifications](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications).

#### DePool fees

All staking commands are subject to an additional fee (by default 0.5 tons), that is partially spent to pay for DePool executing the command. The change is then returned to the sender. This value can be adjusted in TONOS-CLI config.

Additionally, when DePool receives the stake and rewards back from elector and processes the funds of participants, it uses the rewards to top up its balance:

1. first to `m_balanceThreshold` = DePool's balance at the time of deployment - 5 tons
2. then it takes `retOrReinvFee*(N+1)` tokens, where N is the number of participants.`retOrReinvFee` is set to 0,04 tons in the current version of DePool and can only be changed in contract code. It can be viewed through `getDePoolInfo`get-method.

These two fees cover DePool's operational expenses and are deducted only from validation rewards. If DePool doesn't receive rewards in a round, it will not be able to top up its balance.

### Configure TONOS-CLI for DePool operations

For all commands listed below, the DePool address, the wallet making the stake, the amount of fee to pay for DePool's services and the path to the keyfile/seed phrase may be specified in the TONOS-CLI config file in advance:

```bash
tonos-cli config --addr <address> --wallet <address> --keys <path_to_keys or seed_phrase> --depool_fee <depool_fee>
```

Where

`--addr <address>` - the address of the DePool

`--wallet <address>` - the address of the wallet making the stake

`<path_to_keys or seed_phrase>` - either the keyfile for the wallet making the stake, or the seed phrase in quotes

`--depool_fee <depool_fee>` - value in tons, that is additionally attached to the message sent to the DePool to cover its fees. Change is returned to the sender. The default value, used if this option isn't configured, is 0.5 tons. It should be increased only if it proves insufficient and DePool begins to run out of gas on execution.

Example:

```bash
tonos-cli config --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --keys "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel" --depool_fee 0.8
```

In this case all commands allow to omit `--addr`, `--wallet` and `--sign` options.

### Deposit stakes

### 1) Ordinary stake

Ordinary stake is the most basic type of stake. It and the rewards from it belong to the wallet that made it.

It is invested completely in the current pooling round, and can be reinvested every second round (as odd and even rounds are handled by DePool separately). Thus to participate in every DePool round, an ordinary stake should be invested in two consecutive rounds, so it can later be reinvested in odd and even rounds both.

Ordinary stake must exceed DePool minimum stake. Check [DePool Info](https://docs.ton.dev/86757ecb2/v/0/p/37a848-run-depool/t/252d79) to find out the minimum stake.

```bash
tonos-cli depool [--addr <depool_address>] stake ordinary [--wallet <msig_address>] --value <number> [--sign <key_file or seed_phrase>]
```

here

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet making a stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`<key_file or seed_phrase>` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake ordinary --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 100.5 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### 2) Vesting stake

Any wallet can make a vesting stake into round and define a target participant address (beneficiary) who will own this stake. But not the whole stake is available to the beneficiary at once. Instead it is split into parts and the next part of stake becomes available to the beneficiary (is transformed into beneficiary's ordinary stake) at the end of the round that coincides with the end of the next withdrawal period. Rewards from vesting stake are always added to the beneficiary's ordinary stake. To withdraw these funds, beneficiary should use use one of the withdrawal functions.

Please note, that the vesting stake is split into two equal parts by the DePool, to be used in both odd and even rounds, so to ensure DePool can participate in elections with just one vesting stake where validator wallet is beneficiary, the stake should exceed `validatorAssurance` *2. Similarly, to ensure any vesting stake is accepted, make sure it exceeds `minStake` *2.

**Vesting for validator beneficiaries is subject to additional rules:** At the end of every withdrawal period, the part of the vesting stake to be released is divided proportionally into 2 parts - for rounds in this period when DePool successfully completed validation and received a reward (without slashing) and for rounds when DePool missed elections or was slashed. The portion of the stake corresponding to the successful rounds is sent to the validator, while the portion corresponding to the failed rounds is returned to the vesting stake owner. For example, if there were 100 rounds within the withdrawal period, and DePool successfully completed 80 of them, missed elections in 5 more and was slashed in the remaining 15, the validator will receive 80% of the unlocked part of the vesting stake, and the stake owner will get back 20% of it.

Use the following command to make a vesting stake:

```bash
tonos-cli depool [--addr <depool_address>] stake vesting [--wallet <msig_address>] --value <number> --total <days> --withdrawal <days> --beneficiary <address> [--sign <key_file or seed_phrase>]
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet making a stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`total <days>` - total period, for which the stake is made.

`withdrawal <days>` - withdrawal period (each time a withdrawal period ends, a portion of the stake is released to the beneficiary).

> There are limitations for period settings: `withdrawalPeriod` should be <= `totalPeriod`, `totalPeriod` cannot exceed 18 years or be <=0, `totalPeriod` should be exactly divisible by withdrawalPeriod.

`beneficiary <address>` - address of the wallet that will receive rewards from the stake and, in parts over time, the vesting stake itself. Cannot be the same as the wallet making the stake.

`<key_file or seed_phrase>` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake vesting --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 1000 --total 360 --withdrawal 30 --beneficiary 0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

> **Note**: Each participant can be the beneficiary of only one vesting stake.

### 3) Lock stake

Any wallet can make a lock stake, in which it locks its funds in DePool for a defined period, but rewards from this stake will be payed to another target participant (beneficiary). Like vesting stake, lock stake can be configured to be unlocked in parts at the end of each round that coincides with the end of the next withdrawal period. At the end of each period the Lock Stake is returned to the wallet which locked it. The rewards of a lock stake are always added to the ordinary stake of the beneficiary. To withdraw these funds, beneficiary should use use one of the withdrawal functions.

Please note that the lock stake is split into two equal parts by the DePool, to be used in both odd and even rounds, so to ensure DePool can participate in elections with just one lock stake where validator wallet is beneficiary, the stake should equal `validatorAssurance` *2. Similarly, to ensure any vesting stake is accepted, make sure it exceeds `minStake` *2.

Use the following command to make a lock stake:

```bash
tonos-cli depool [--addr <depool_address>] stake lock [--wallet <msig_address>] --value <number> --total <days> --withdrawal <days> --beneficiary <address> [--sign <key_file or seed_phrase>]
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet making a stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`total <days>` - total period, for which the stake is made. 

`withdrawal <days>` - withdrawal period (each time a withdrawal period ends, a portion of the stake is returned to the wallet that made the stake). 

> There are limitations for period settings: `withdrawalPeriod` should be <= `totalPeriod`, `totalPeriod` cannot exceed 18 years or be <=0, `totalPeriod` should be exactly divisible by withdrawalPeriod.

`beneficiary <address>` - address of the wallet that will receive rewards from the stake. Cannot be the same as the wallet making the stake.

`key_file or seed_phrase` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake lock --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 1000 --total 360 --withdrawal 30 --beneficiary 0:f22e02a1240dd4b5201f8740c38f2baf5afac3cedf8f97f3bd7cbaf23c7261e3 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

> **Note**: Each participant can be the beneficiary of only one lock stake.

### Remove stakes

This command removes an ordinary stake from a pooling round (while it has not been staked in the Elector yet):

```bash
tonos-cli depool [--addr <depool_address>] stake remove [--wallet <msig_address>] --value <number> [--sign <key_file or seed_phrase>]
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet that made the stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`<key_file or seed_phrase>` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake remove --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 100 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### Transfer stakes

The following command assigns an existing ordinary stake or its part to another participant wallet. If the entirety of the stake is transferred, the transferring wallet is removed from the list of participants in the DePool. If the receiving wallet isn't listed among the participants, it will become a participant as the result of the command.

```bash
tonos-cli depool [--addr <depool_address>] stake transfer [--wallet <msig_address>] --value <number> --dest <address> [--sign <key_file or seed_phrase>]
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet that made the stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`dest <address>` - address of the new owner of the stake.

`<key_file or seed_phrase>` - either the keyfile for the wallet making the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake transfer --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 1000 --dest 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### Withdraw Stakes

### 1) Withdraw entire stake

The following command allows to withdraw an ordinary stake to the wallet that owns it, as soon as the stake becomes available. Use `withdraw on` to receive the stake, once it's unlocked. If you then make another stake, and want to keep reinvesting it every round, run the command with `withdraw off`.

```bash
tonos-cli depool [--addr <depool_address>] withdraw on | off [--wallet <msig_address>] [--sign <key_file or seed_phrase>]
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet that made the stake.

`<key_file or seed_phrase>` - either the keyfile for the wallet that made the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace withdraw on --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

### 2) Withdraw part of the stake

The following command allows to withdraw part of an ordinary stake to the wallet that owns it, as soon as the stake becomes available. If, as result of this withdrawal, participant's ordinary stake becomes less than `minStake`, then participant's whole stake is sent to participant.

```bash
tonos-cli depool [--addr <depool_address>] stake withdrawPart [--wallet <msig_address>] --value <number> [--sign <key_file or seed_phrase>]
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet that made the stake.

all `--value` parameters must be defined in tons, like this: `--value 10.5`, which means the value is 10,5 tons.

`<key_file or seed_phrase>` - either the keyfile for the wallet that made the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace stake withdrawPart --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --value 1000 --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

## Reinvest Stakes

Ordinary stake reinvestment is controlled by the DePool [reinvest flag](https://docs.ton.dev/86757ecb2/p/45d6eb-depool-specifications/t/82306f). By default this flag is set to `yes`, and the the participant's available ordinary stake will be reinvested every round, no additional action required.
It gets set to `no` when withdrawing the entire stake. After stake withdrawal it remains set to `no`.
To re-enable ordinary stake reinvesting after withdrawing a stake, run the withdraw command with option `off`:

```bash
tonos-cli depool [--addr <depool_address>] withdraw off [--wallet <msig_address>] [--sign <key_file or seed_phrase>]
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet that made the stake.

`<key_file or seed_phrase>` - either the keyfile for the wallet that made the stake, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace withdraw off --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

**Note:**

Withdrawing a part of the stake does not affect the reinvest flag.

Lock and vesting stakes are reinvested according to their initial settings for the full duration of the staking period. There is no way to change these settings once lock and vesting stakes are made.

## 9. Check Stakes in the DePool

After the stake is made, you can check its status in the DePool with the `getParticipantInfo` get-method:

```bash
tonos-cli run <depool_address> getParticipantInfo '{"addr":"<msig_address>"}' --abi DePool.abi.json
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet that made the stake.

## 10. Set Up Validator Script

Once the the validator has accumulated a stake sufficient to participate in elections, (at least `validatorAssurance`), this stake needs to be signed by the node. This should be done through a validator script.

The main function that the validator script should regularly perform is to send signed election requests to the DePool, which will forward the accumulated stake to the Elector contract on the validator's behalf. The Election request should be generated with the proxy address for the current round as the requesting validator wallet.

> When participating in elections through a DePool contract, the validator script handles only the creation and sending of the node election request, as all activities regarding stakes and rewards handled at the level of the DePool.

Working examples of such a script can be found here: for the [main FreeTON](https://github.com/tonlabs/main.ton.dev/blob/master/scripts/validator_depool.sh) network, and for the [devnet](https://github.com/tonlabs/net.ton.dev/blob/master/scripts/validator_depool.sh).

> Important: If you are setting up DePool validator script on top of a node, that was previously functioning under a regular validator script, you should first disable the regular script (validator_msig.sh) and only set up the DePool validator script (validator_depool.sh) for the next elections. Two validator scripts should never run at the same time, as this creates unpredictable behavior.

It is recommended to run the script periodically, for example with `cron` utility. Example:

```bash
@hourly        script --return --quiet --append --command "cd /scripts/ && ./validator_depool.sh 2>&1" /var/ton-work/validator_depool.log
```

> Note, that the validator wallet should have a small sum of tokens (~20 Tons) available at all times to reliably send election requests to DePool. Each election request costs ~ 1 Ton.

> Note: Do not forget to confirm the election request transactions sent out by the script with the necessary amount of validator wallet custodians.

It is possible to configure the script to monitor the DePool status through the available get-methods, such as `getParticipantInfo`, `getRounds`, `getDePoolInfo`, `getParticipants` (see [DePool specs](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications) for details) and through [view DePool events command](https://github.com/tonlabs/tonos-cli/#view-depool-events).

## 11. Maintain Positive Balance on DePool and Supplementary Contracts

### DePool Balance

Normally the DePool receives sufficient funds for its operations from validation rewards. They go to DePool's own balance, which is completely separate from the staking pool and the funds on it are never staked.

However, a situation where the DePool spends its funds on regular operations, but does not receive enough rewards (for example, fails to participate in the elections or loses them), is possible.

DePool balance can be viewed or through `getDePoolBalance` get-method in TONOS-CLI (requires `DePool.abi.json` file):

```bash
tonos-cli run <depool_address> getDePoolBalance {} --abi DePool.abi.json
```

Additionally, DePool emits the `TooLowDePoolBalance` event when its balance drops too low to perform state update operations (below `CRITICAL_THRESHOLD` which equals 10 tons).

Replenish the balance to at least 20 tons from any multisignature wallet with the following command:

```bash
tonos-cli depool [--addr <depool_address>] replenish --value *number* [--wallet <msig_address>] [--sign <key_file or seed_phrase>]
```

Where

`<depool_address>` - address of the DePool contract.

all `--value` parameters must be defined in tons, like this: `--value 150.5`, which means the value is 150,5 tons.

`<msig_address>` - address of the wallet that made the stake.

`<key_file or seed_phrase>` - either the keyfile for the wallet, or the seed phrase in quotes.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace replenish --value 150 --wallet 0:1b91c010f35b1f5b42a05ad98eb2df80c302c37df69651e1f5ac9c69b7e90d4e --sign "dizzy modify exotic daring gloom rival pipe disagree again film neck fuel"
```

> Note: These funds do not go towards any stake. They are transferred to the DePool contract itself and are spent on its operational expenses.

### Proxy Balance

The balance of ~ 2 Tons on the proxies should be maintained for the full duration of DePool existence.

**Generally proxies receive fees for their services automatically, but if they run out of funds for any reason, DePool might miss elections.**

As the proxies are deployed by the DePool itself, you have to run the `getDePoolInfo` get-method to find out their addresses:

```bash
tonos-cli run <depool_address> getDePoolInfo {} --abi DePool.abi.json
```

The balance of the proxies can be viewed on the [ton.live](https://ton.live/main) blockchain explorer by searching the proxy addresses, or through TONOS-CLI commands:

```bash
tonos-cli account <proxy0_address>
tonos-cli account <proxy1_address>
```

If necessary, it can be topped up with a [transaction](https://docs.ton.dev/86757ecb2/v/0/p/94921e-multisignature-wallet-management-in-tonos-cli/t/7554a3) from any multisignature wallet:

```bash
tonos-cli call <wallet_address> submitTransaction '{"dest":"<proxy_address>","value":*number*,"bounce":"true","allBalance":"false","payload":""}' --abi <MultisigWallet.abi.json> --sign <wallet_seed_or_keyfile>
```

Where

`<wallet_address>` - is the address of the wallet, from which you are making the transaction

`<proxy_address>` - address of one of the proxies, calculated on step 4.

`"value":*number*` - the amount of coins to be transferred (in nanotokens).

`<MultisigWallet.abi.json>` - the ABI file of the contract, from which you are making the transaction (for validator wallets - usually `SafeMultisigWallet.abi.json`)

`<wallet_seed_or_keyfile>` - either the seed phrase in double quotes, or the path to the keyfile for the wallet, from which you are making the transaction

> **Note**: If the proxy balance dips too low to operate and it fails to deliver messages between DePool and elector, DePool will emit one of the following events: `ProxyHasRejectedTheStake` (if proxy cannot pass the stake on to elector) or `ProxyHasRejectedRecoverRequest` (if proxy cannot retrieve stake from elector). To reestablish operations you need to top up the proxy balance, and then call the DePool `ticktock` function by any available means. These measures should be taken as soon as possible, however, as DePool risks missing elections if it cannot communicate with elector on time.

### DePool Helper Balance

The balance of ~ 100 Tons on the helper contract should be maintained for the full duration of DePool existence.

The balance of the helper can be viewed on the [ton.live](https://ton.live/main) blockchain explorer by searching the helper address, or through TONOS-CLI command:

```bash
tonos-cli account <helper_address>
```

Helper balance should be topped up regularly, depending on the set timer period. Without funds on the Helper contract, DePool will not be able to function regularly.

To top up, send a [transaction](https://docs.ton.dev/86757ecb2/v/0/p/94921e-multisignature-wallet-management-in-tonos-cli/t/7554a3) from any multisignature wallet:

```bash
tonos-cli call <wallet_address> submitTransaction '{"dest":"<helper_address>","value":*number*,"bounce":"true","allBalance":"false","payload":""}' --abi <MultisigWallet.abi.json> --sign <wallet_seed_or_keyfile>
```

Where

`<wallet_address>` - is the address of the wallet, from which you are making the transaction.

`<helper_address>` - address of the helper, calculated on step 4.

`"value":*number*` - the amount of coins to be transferred (in nanotokens).

`<MultisigWallet.abi.json>` - the ABI file of the contract, from which you are making the transaction (for validator wallets - usually `SafeMultisigWallet.abi.json`).

`<wallet_seed_or_keyfile>` - either the seed phrase in double quotes, or the path to the keyfile for the wallet, from which you are making the transaction.

### Validator Wallet Balance

Validator wallet will receive a fraction of any DePool round rewards directly, so with a successful DePool setup, it should receive regular income.

In general, the validator wallet should have a small sum of tokens (~20 Tons) available at all times to reliably send election requests to DePool. Each election request costs ~ 1 Ton.

## 12. Check DePool Status in the Elections

Once everything has been configured properly, stakes made, and election request sent by the validator script, you can monitor the operation of the DePool and its validator node through various channels.

### On ton.live

Nodes currently participating in an open election are displayed on [ton.live](https://ton.live/validators?section=all) in the **Next** validators section until election end.

When the elections end, the newly elected set of validators is posted on [ton.live](https://ton.live/validators?section=all) in the **Next** validators section.

When the new validator set becomes active, it is moved to the **Current** section. At that point you will be able to see new blocks signed by the validator node on its validator page.

To find the page of your node, you need to know your **ADNL** (Abstract Datagram Network Layer) **address**. It is the unique identifier of your node and is generated anew for every election cycle. It is stored in the `~/ton-keys/elections/server-election-adnl-key` file.

Copy the key in the `created new key` line and enter it in the search field on [ton.live](https://ton.live/validators?section=all) to locate and open your validator node page (make sure you have selected the network your node is connected to, e.g `main.ton.dev`, `net.ton.dev`).

### Using DePool Events

TONOS-CLI supports DePool [event](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications/t/568692) monitoring.

To print out all events, or, optionally, all events since a specific time use the following command:

```bash
tonos-cli depool [--addr <depool_address>] events [--since <utime>]
```

Where

`<depool_address>` - address of the DePool contract.

`<utime>` - unixtime, since which the events are displayed. If `-since` is omitted, all DePool events are printed.

To wait for a new event use the following command.

```bash
tonos-cli depool [--addr <depool_address>] events --wait-one
```

Where

`<depool_address>` - address of the DePool contract.

TONOS-CLI waits until new event will be emitted and then prints it to the stdout.

Example:

```bash
tonos-cli depool --addr 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace events --wait-one
```

**List of possible events:**

1. `DePoolClosed()` - event emitted when DePool is closing.
2. `RoundStakeIsAccepted(uint64 queryId, uint32 comment)` - event emitted when Elector accepts the stake.
3. `RoundStakeIsRejected(uint64 queryId, uint32 comment)` - event emitted when Elector rejects the stake.
4. `ProxyHasRejectedTheStake(uint64 queryId)` - event is emitted if stake is returned by proxy because too low balance of proxy contract.
5. `ProxyHasRejectedRecoverRequest(uint64 roundId)` - event is emitted if stake cannot be returned from elector because too low balance of proxy contract.
6. `RoundCompleted(TruncatedRound round)` - event emitted when the round was completed.
7. `StakeSigningRequested(uint32 electionId, address proxy)` - event emitted when round switches from pooling to election indicating that DePool is waiting for signed election request from validator wallet.
8. `TooLowDePoolBalance(uint replenishment)` - event emitted when DePool's own balance becomes too low to perform state update operations (below `CRITICAL_THRESHOLD` which equals 10 tons). `replenishment` indicates the minimal value required to resume operations. It's recommended to replenish the balance to 20 tons or more if this event occurs.


Events command output example:

```bash
event e70ae29730b1ff2883b5491e8b70a33dce49cbdd17eb459f1a6b5d624f08c100
RoundStakeIsAccepted 1605758581 (2020-11-18 08:03:01.000)
{"comment":"0x0","queryId":"0x5fb5ee53"}

event 73c288cdc1ea8ee76ea5582d1f5b11984059e46ee2768562dc5e6d6d53f7e3b3
StakeSigningRequested 1605758430 (2020-11-18 08:00:30.000)
{"electionId":"0x5fb66db2","proxy":"-1:3187b4d738d69776948ca8543cb7d250c042d7aad1e0aa244d247531590b9147"}

event af3fc9f9d9668577b33d235c8261a2f52308a3b4ba40bd362191104910fae634
RoundCompleted 1605758430 (2020-11-18 08:00:30.000)
{"round":{"completionReason":"0x2","handledStakesAndRewards":"0x0","id":"0x1","isValidatorStakeCompleted":false,"participantQty":"0x0","recoveredStake":"0x0","rewards":"0x0","stake":"0x0","stakeHeldFor":"0x0","step":"0x9","supposedElectedAt":"0x0","unfreeze":"0x0","unused":"0x0","validatorRemainingStake":"0x0","validatorStake":"0x0","vsetHashInElectionPhase":"0x59475fe28466cd18ecff693a356604497b758b2f0c562f55d2d2922f0776dbf2"}}
```

### Using get-methods

DePool contract supports a number of get-methods, which can be used to monitor its status and the status of participants and stakes in the pool.

### `getParticipantInfo(address addr)`

Returns information about a specific participant in all investment rounds.

```bash
tonos-cli run <depool_address> getParticipantInfo '{"addr":"<msig_address>"}' --abi DePool.abi.json
```

Where

`<depool_address>` - address of the DePool contract.

`<msig_address>` - address of the wallet that made the stake.

Output example:

```bash
Result: {
  "locks": {
    "0x54": {
      "lastWithdrawalTime": "0x5fa517f7",
      "owner": "0:de7dc920ff73ae077035f26715986aa8039eadbec25f525a0b8fb15dfc74ad0b",
      "remainingAmount": "0x5af32e47a500",
      "withdrawalPeriod": "0x1a5e00",
      "withdrawalValue": "0x5af32e47a500"
    },
    "0x55": {
      "lastWithdrawalTime": "0x5fa517f7",
      "owner": "0:de7dc920ff73ae077035f26715986aa8039eadbec25f525a0b8fb15dfc74ad0b",
      "remainingAmount": "0x5af32e47a500",
      "withdrawalPeriod": "0x1a5e00",
      "withdrawalValue": "0x5af32e47a500"
    }
  },
  "reinvest": true,
  "reward": "0x106dbf302591",
  "stakes": {
    "0x54": "0x51779432da5",
    "0x55": "0x72653cb14c1ec"
  },
  "total": "0x7e151a0e73991",
  "vestings": {},
  "withdrawValue": "0x0"
}
```

The participant parameters displayed by the get-method are the following:

`locks` and `vestings`: participant's lock and vesting stakes, each split into two neighboring rounds. There can be only one of each, split equally into two entries. The parameters of the lock and vesting stakes are:
- `lastWithdrawalTime`: last time a withdrawal period ended and a part of the stake was unlocked (in unixtime).
- `owner`: the address that made the lock or vesting stake on behalf of the participant.
- `remainingAmount`: the current amount staked in this round (in nanotons).
- `withdrawalPeriod`: the period in seconds, after which the next part of the stake gets unlocked.
- `withdrawalValue`: the value that is unlocked every withdrawal period (in nanotons).

`reinvest`: whether the ordinary stake of the participant should be continuously reinvested.

`reward`: The total rewards earned by participant in the current DePool (in nanotons).

`stakes`: the ordinary stakes in the current active rounds (in nanotons).

`total`: participant's total stake (in nanotons).

### `getDePoolInfo()`

Returns DePool configuration parameters and constants (supplementary contract addresses, minimal stake settings and fees for various actions).

```bash
tonos-cli run <depool_address> getDePoolInfo {} --abi DePool.abi.json
```

Where

`<depool_address>` - address of the DePool contract.

Output example:

```bash
Result: {
  "minStake": "0x2540be400",
  "participantRewardFraction": "0x5f",
  "poolClosed": false,
  "proxies": [
    "-1:5fb31e06ea510818111fc4ede1f7ce16137c9deafa430a8d7f623cdb05256a8b",
    "-1:97396aa81c9ef4d47780bd38d4b54ed32bb790d8db6a8380d513a444ba165dbb"
  ],
  "proxyFee": "0x55d4a80",
  "retOrReinvFee": "0x2625a00",
  "stakeFee": "0x1dcd6500",
  "validatorAssurance": "0xd18c2e2800",
  "validatorRewardFraction": "0x5",
  "validatorWallet": "0:de7dc920ff73ae077035f26715986aa8039eadbec25f525a0b8fb15dfc74ad0b"
}
```

The round parameters displayed by the get-method are the following:

  `minStake`: the minimal stake the DePool accepts from participants (in nanotons). Set during deployment.
  
  `participantRewardFraction`: percentage of the reward that goes to all participants. Also set during deployment.
  
  `poolClosed`: whether DePool was closed.
  
  `proxies`: the two proxies on the masterchain that DePool uses to communicate with elector. They are deployed by the DePool itself.
  
  `proxyFee`: the fee that proxies take for any messages passed through them (in nanotons).
  
  `retOrReinvFee`: the fee deducted from every participant's stake and rewards during reward distribution at the end of the round (in nanotons).
  
  `stakeFee`: fee for staking operations (in nanotons).
  
  `validatorAssurance`: required validator stake (in nanotons). Also set during deployment.
  
  `validatorRewardFraction`: the fraction of the total reward that goes directly to validator. Equals 100% - `participantRewardFraction`.
  
  `validatorWallet`: the address of the validator wallet. Also set during deployment.
  
  
### `getRounds()`

Returns information about all rounds (step, total stake, stakeholder count, round id).

```bash
tonos-cli run <depool_address> getRounds {} --abi DePool.abi.json
```

Where

`<depool_address>` - address of the DePool contract.

Output example:

```bash
Result: {
  "rounds": {
    "0x8": {
      "completionReason": "0x5",
      "handledStakesAndRewards": "0x5a757ecd1c42",
      "id": "0x8",
      "isValidatorStakeCompleted": true,
      "participantQty": "0x3",
      "recoveredStake": "0x5a913869b7e3",
      "rewards": "0x20e13cf2ed9",
      "stake": "0x58676afded6a",
      "stakeHeldFor": "0x8000",
      "step": "0x9",
      "supposedElectedAt": "0x5fb36db2",
      "unfreeze": "0x5fb4edb2",
      "unused": "0x0",
      "validatorRemainingStake": "0x0",
      "validatorStake": "0x4e25ac5e583e",
      "vsetHashInElectionPhase": "0xd5849d05c86ff00b772f82c891fada739c3862f81517e8a9dba0926750ff9ac2"
    },
    "0x9": {
      "completionReason": "0x0",
      "handledStakesAndRewards": "0x0",
      "id": "0x9",
      "isValidatorStakeCompleted": false,
      "participantQty": "0x2",
      "recoveredStake": "0x0",
      "rewards": "0x0",
      "stake": "0x1500ef1ef5d32",
      "stakeHeldFor": "0x8000",
      "step": "0x4",
      "supposedElectedAt": "0x5fb4c4dc",
      "unfreeze": "0xffffffff",
      "unused": "0x0",
      "validatorRemainingStake": "0x0",
      "validatorStake": "0x14abce2c35932",
      "vsetHashInElectionPhase": "0xd19ee153b78ded323a0d311af9807b23b91e4ecce41ae538da53363bab2575f8"
    },
    "0xa": {
      "completionReason": "0x0",
      "handledStakesAndRewards": "0x0",
      "id": "0xa",
      "isValidatorStakeCompleted": false,
      "participantQty": "0x1",
      "recoveredStake": "0x0",
      "rewards": "0x0",
      "stake": "0xb2d05e00",
      "stakeHeldFor": "0x0",
      "step": "0x1",
      "supposedElectedAt": "0x0",
      "unfreeze": "0xffffffff",
      "unused": "0x0",
      "validatorRemainingStake": "0x0",
      "validatorStake": "0x0",
      "vsetHashInElectionPhase": "0x0"
    },
    "0xb": {
      "completionReason": "0x0",
      "handledStakesAndRewards": "0x0",
      "id": "0xb",
      "isValidatorStakeCompleted": false,
      "participantQty": "0x1",
      "recoveredStake": "0x0",
      "rewards": "0x0",
      "stake": "0x77359400",
      "stakeHeldFor": "0x0",
      "step": "0x0",
      "supposedElectedAt": "0x0",
      "unfreeze": "0xffffffff",
      "unused": "0x0",
      "validatorRemainingStake": "0x0",
      "validatorStake": "0x0",
      "vsetHashInElectionPhase": "0x0"
    }
  }
}
```

The round parameters displayed by the get-method are the following:

`completionReason`: the code for the reason the round was completed. Remains "0x0", until round actually is completed. The possible reasons are:

- 0x0 - Round is not completed yet.
- 0x1 - Pool was closed by owner.
- 0x2 - The round was one of the first two rounds after deployment: 0x0 or 0x1. These first rounds are empty and are used only to launch the round rotation mechanism. They complete with this code without performing any additional actions.
- 0x3 - Validator stake is less than validatorAssurance.
- 0x4 - Stake is rejected by elector for some reason.
- 0x5 - Round is completed successfully. DePool won elections, its node performed validation and it received the reward from elector.
- 0x6 - DePool has participated in elections but lost the elections.
- 0x7 - Validator is blamed during investigation phase.
- 0x8 - Validator sent no request during election phase.

`handledStakesAndRewards`: the total quantity of stakes and rewards that were processed by the DePool during [Completing](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications/t/13b9d0) step (in nanotons).

`id`: round ID. It's also displayed above each round. At DePool deployment, the first four rounds are created: 0x0, 0x1, 0x2 and 0x3. Whenever one round completes and is removed from the DePool, a new one is created, its ID incremented by 1: when 0x0 is removed, 0x4 is created, etc.

`isValidatorStakeCompleted`: indicates whether validator's stake has been processed during [Completing](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications/t/13b9d0) round step. Whenever participants receive rewards, validator's stake should be processed first, as any losses the total stake sustains due to poor node rerformance are first deducted from validator's share of the pool.

`participantQty`: the quantity of participants in the round.

`recoveredStake`: the total stake returned by elector (in nanotons).

`rewards`: the total rewards that are distributed among all participants in the current round (in nanotons). Is calculated when the stake is returned from elector.

`stake`: the total stake in the current round, that is sent to elector (in nanotons).

`stakeHeldFor`: the period in seconds for which stake will remain frozen in elector after validation. It's set by the global configuration parameter p15 when validation completes.

`step`: [step the round is currently at](https://docs.ton.dev/86757ecb2/v/0/p/45d6eb-depool-specifications/t/13b9d0). The possible steps are:

- 0x0 - PrePooling: step reserved for receiving half of vesting/lock stake from participants. Nothing else happens when round is in this step.
- 0x1 - Pooling: DePool receives stakes from participants. Half of vesting/lock stakes are invested into the round in the pooling step, the other into the round in the PrePooling step. This way, the other half of these stakes is always invested into the very next round.
- 0x2 - WaitingValidatorRequest: waiting for election request from validator. The elections have begun, it's no longer possible to invest stakes into this round. Once election request from validator is received, DePool can participate in elections.
- 0x3 - WaitingIfStakeAccepted: stake has been sent to elector. Waiting for answer from elector.
- 0x4 - WaitingValidationStart: elector has accepted round stake. Validator is candidate. Waiting for validation to start, to know if validator won elections.
- 0x5 - WaitingIfValidatorWinElections: DePool has tried to recover stake in validation period to know if validator won elections. Waiting for elector answer.
- 0x6 - WaitingUnfreeze: DePool received elector answer and waits for the end of unfreeze period. If at this step CompletionReason!=0x0, then validator did not win and DePool is waiting to return/reinvest funds after the next round. Else validator won elections.
- 0x7 - WaitingReward: Unfreeze period has been ended. Request to recover stake has been sent to elector. Waiting for answer from elector.
- 0x8 - Completing: Returning or reinvesting participant stakes because round is completed.
- 0x9 - Completed: All stakes of the round have been returned or reinvested. At the next round rotation the round will be deleted from the DePool.

`supposedElectedAt`: the time the validator is scheduled to start validating, if elected (in unixtime). This value remains 0x0, until validator elections start and DePool enters `waitingValidatorRequest` step of the round. Then it is set to the time the election winners will start validating.

`unfreeze`: the time the stake will be unfrozen by elector (in unixtime). This value remains 0xffffffff until validation ends.

`unused`: if the stake was cut off by the elector (this can happen if there is a significant number of election candidates with much smaller stakes), this value equals the amount cut off (in nanotons). This amount is not lost to participants - it simply isn't staked in this round and the rewards for the round will be proportionally smaller.

`validatorRemainingStake`: this value is used if validator got punished by elector for poor node performance and part of the DePool stake is lost. Then this value equals the remaining validator stake, if any (in nanotons).

`validatorStake`: this value equals the final validator stake in the current round. It is set at the and of the Pooling step.

`vsetHashInElectionPhase`:  this is a system variable that holds the hash of validation set (global config parameter 34) when round was in election phase. Is set during election.


### `getParticipants()`

Returns list of all participants.

```bash
tonos-cli run <depool_address> getParticipants {} --abi DePool.abi.json
```

Where

`<depool_address>` - address of the DePool contract.

Output example:

```bash
Result: {
  "participants": [
    "0:9fa316f41fe4e991865b80006c9d9916b2637146e9a6f346eeb25c035206c5b7",
    "0:a08bb1f6c64939bcbd3d950a44d88820f0102c550bfaf49f70f2d012eeec333a",
    "-1:68384476fce1d2649484912c08541a8037c36b606aca0f8cc04c043640e8dd98"
  ]
}
```

### `getDePoolBalance()`

Returns DePool's own balance in nanotokens (without stakes).

```jsx
tonos-cli run <depool_address> getDePoolBalance {} --abi DePool.abi.json
```

Where

`<depool_address>` - address of the DePool contract.


## 13. (Optional) Adjust validator and participant reward fraction

If you want to make your DePool more attractive to potential participants, you may increase the fraction of the total reward they receive.

DePool deployment keys are required for this action. Use the following command:

```bash
tonos-cli call <depool_address> setValidatorRewardFraction '{"fraction":<fraction_value>}' --abi DePool.abi.json --sign <depool_keyfile_or_seed_phrase>
```

Where

`<depool_address>` - address of the DePool.

`<fraction_value>` - new value of Validators reward fraction, which should be less than previous and should not be equal to 0.

`<depool_keyfile_or_seed_phrase>` - DePool deployment keyfile or its corresponding seed phrase.

Example:

```bash
tonos-cli call 0:53acdc8033cc0794125038a810d4b64e24e72add52ee866b82ade42d12cd9f02 setValidatorRewardFraction '{"fraction":29}' --abi DePool.abi.json --sign depool.keys.json
```

Current validator reward fraction value can be viewed with the `getDePoolInfo` get-method.


## 14. (Optional) Close DePool

The deployer of the DePool can close the DePool at any time. DePool deployment keys are required for this action:

```bash
tonos-cli call <depool_address> terminator {} --abi DePool.abi.json --sign <depool_keyfile_or_seed_phrase>
```

Where

`<depool_address>` - address of the DePool.

`<depool_keyfile_or_seed_phrase>` - DePool deployment keyfile or its corresponding seed phrase.

Example:

```bash
tonos-cli call 0:37fbcb6e3279cbf5f783d61c213ed20fee16e0b1b94a48372d20a2596b700ace terminator {} --abi DePool.abi.json --sign depool.json
```

When a DePool is closed, all the stakes invested in it are returned to their owners, as soon as they become available. `dePoolClosed` event is emitted. The closed DePool cannot be reactivated again.

# Rewards Distribution

Every time DePool receives rewards for validation, DePool replenishes it's own balance and  the rest is distributed according to the following rules:

1) `validatorRewardFraction`% of the reward, regardless of the validator’s share in the pool, goes directly to the validator wallet. This is the reward for maintaining the node and is intended to be used on operational expenses.

2) `participantRewardFraction`% of the reward is distributed among all participants (including the validator) proportionally to their share of the staking pool. By default these rewards are added to the ordinary stakes of all participants and reinvested with it. To withdraw this stake or any part of it to the participant wallet, use one of the withdrawal functions.


# Troubleshooting

## 1. Wrong contract version

**Issue**: Wrong/outdated version of any contracts involved in DePool operations may cause various issues and hard-to-diagnose behavior.

To check contract versions, search for the addresses of DePool, DePool Helper and both proxies on [ton.live](http://ton.live) and, under **More details**, review **Code hash** (click on the value to copy it to clipboard).

It should match the following values:

DePool:

`a46c6872712ec49e481a7f3fc1f42469d8bd6ef3fae906aa5b9927e5a3fb3b6b`

Proxies:

`481d7f583b458a1672ee602f66e8aa8d2f99d3cd9ece2eaa20e25c7ddf4c7f4a`

DePool Helper:

`f990434c02c2b532087782a2d615292c7c241ece4a9af33f8d090c535296401d`

If only the Helper contract has wrong Code hash, deploying and configuring only a new Helper is enough.

If DePool or proxies have wrong Code hash, all contracts have to be redeployed, and the node reconfigured to work with the new DePool.

## 2. DePool isn't emitting events

**Issue**: DePool seems to be set up correctly, but is not emitting expected events, for example `stakeSigningRequested`.

This can be caused by issues with the DePool Helper contract, its connection to the global timer, or the global timer itself. 

**Possible solutions:**

1. Change the global timer and/or the timer call period (termporarily unavailable):

    ```bash
    tonos-cli call <HelperAddress> initTimer '{"timer":"TimerAddress","period":*number*}' --abi DePoolHelper.abi.json --sign helper.json
    ```

    Where

    `<HelperAddress>` – is the address of the Helper contract from step 4.2

    `<TimerAddress>` - is the address of the global timer contract.

    `"period":*number*` - is the period for regular DePool contract calls via ticktock messages (in seconds).

2. Set up external ticktock function call through TONOS-CLI:

    ```bash
    tonos-cli call <HelperAddress> sendTicktock {} --abi DePoolHelper.abi.json --sign helper.json
    ```

    Where

    `<HelperAddress>` – is the address of the Helper contract from step 4.2.

    If necessary, run it regularly, e.g. with cron:

    ```bash
    @hourly        cd <tonos-cli-dir> && tonos-cli call <HelperAddress> sendTicktock {} --abi DePoolHelper.abi.json --sign helper.json
    ```

    Where

    `<tonos-cli-dir>` - directory with TONOS-CLI configuration file, `DePoolHelper.abi.json` file and `helper.json` keyfile containing DePool Helper keys.

    `<HelperAddress>` – is the address of the Helper contract from step 4.2.

3. Call DePool's ticktock function through multisig instead of Helper:

    ```bash
    tonos-cli depool [--addr <depool_address>] ticktock [-w <msig_address>] [-s <path_to_keys_or_seed_phrase>]
    ```

    Where

    `--addr <depool_address>` - the address of the DePool

    `-w <msig_address>` - the address of the multisig wallet used to call DePool

    `-s <path_to_keys_or_seed_phrase>` - either the keyfile for the wallet making the stake, or the seed phrase in quotes

    All these options can be skipped, if they were previously specified in the TONOS-CLI configuration file.

    1 token is always attached to this call, change is returned to sender.

## 3. Validator script and election request issues

**Issue**: DePool isn't receiving election request from validator script and/or isn't passing it on to the Elector.

This can be caused by DePool setup errors, low balance on some of the contracts involved, or issues with the script or node setup.

**Possible solutions and diagnostic methods**:

1.  If the DePool fails to accumulate a suitable stake, or malfunctions in any other manner, the election request will not pass through to the Elector. Always make sure that the full DePool setup procedure described in this document is completed, and that DePool contract itself operates correctly, i.e. enters waiting request step and emits `stakeSigningRequested` event, when encountering problems with election participation.
2. Check balance of all contracts and top up if any of them have run out of funds (see section 11 for details).
3. Check that the DePool address is specified in the in the `~/ton-keys/depool.addr` file in your validator node files and matches your current DePool address.
4. Check that the validator wallet address is specified in the `~/ton-keys/$(hostname -s).addr` file according to the [node setup procedure](https://docs.ton.dev/86757ecb2/p/708260-run-validator/t/906cb8).
5. Check that the validator wallet keys are saved to the `~/ton-keys/msig.keys.json` file according to the [node setup procedure](https://docs.ton.dev/86757ecb2/p/708260-run-validator/t/05caf5).
6. Check validator script output log (`/var/ton-work/validator_depool.log` file if script is set up according to the given example). They may help identify the cause of the issue.
7. Rerun the command to send election request manually. It can be found in the validator script output log (`/var/ton-work/validator_depool.log` file if set up according to the given example) and used as is.

    Example:

    ```bash
    tonos-cli call -1:fd05bd9be4e2d3ee7789d1fbc5811e0bd85cf1d14968028fd46a9e1c7b1066cc submitTransaction '{"dest":"0:10fdf438953430949ca33147f792b9fd9002e7979e50c94547c771c51fb643b9","value":"1000000000","bounce":true,"allBalance":false,"payload":"te6cckEBAgEAmQABqE5zdEsAAAAAXz7BoZOzdxrAyZXWwptpyrV5ZV1EkLrRdSsfm0KFiFpOuB4XXz7FVAADAACIUt3MiEtCLfPfKEWoVz2sTA9yS/Sl8N88ZkQ8CB1c3QEAgNnX/KhAEKVKe/MO4ArCIMLXM1kgYu34Ujp9dSq2lkSo8vfj0s+yySs6Ac2ufavtXO4DLZ1afugAVwUjvKvI3Agoizgf"}' --abi /validation/configs/SafeMultisigWallet.abi.json --sign /keys/msig.keys.json
    ```

8. Run validator script with verbose logs to get more diagnostic information:

    ```bash
    bash -x ./validator_depool.sh
    ```
    
## 4. DePool function terminates with error in TONOS-CLI

In TONOS-CLI output it looks like this:

```bash
message: Contract execution was terminated with error
message_processing_state: null
data: {
  "account_address": "0:3187b4d738d69776948ca8543cb7d250c042d7aad1e0aa244d247531590b9147",
  "config_server": "net.ton.dev",
  "exit_code": 140,
  "function_name": "constructor",
  "original_error": {
    "code": 1006,
    "core_version": "0.27.0",
    "data": {
      "block_id": "20c8932bc6c7baa90c2d099595b432607355b79d95293061dc6feec392675975",
      "block_time": "Thu, 19 Nov 2020 13:24:37 +0300 (1605781477)",
      "expiration_time": "Thu, 19 Nov 2020 13:24:35 +0300 (1605781475)",
      "message_id": "eae70ebcf84fd9ebcffc544908ca637d9a46a8bdffdab24db6749d003608969e",
      "sending_time": "Thu, 19 Nov 2020 13:23:35 +0300 (1605781415)"
    },
    "message": "Message was not delivered within the specified timeout",
    "message_processing_state": null,
    "source": "node"
  },
```

The error code is indicated in the `"exit_code"` line.

Possible error codes and their meanings:

`101` - message sender is not owner (message public key is wrong). Please check your key file or seed phrase.

`108` - function cannot be called by external message.

`113` - message sender is not validator wallet.

`114` - DePool is closed.

`116` - participant with such address does not exist.

`129` - incorrectly defined stake parameters during DePool deployment (`minStake` < 1 token or `minStake` > `validatorAssurance`). Please check your parameters in deploy message.

`130` - DePool deployment isn't signed with public key. Please check your key file or seed phrase.

`133` - validator address passed to constructor is not of add_std type. Please check your parameters in deploy message.

`138` - Incorrect participant reward fraction during DePool deployment (`participantRewardFraction` ≤ 0 or  ≥ 100). Please check your parameters in deploy message.

`141` - incorrectly specified proxy code during DePool deployment. Please check your parameters in deploy message.

`142` - DePool is being deployed to the wrong shardchain (workchain id ≠ 0). Please check your parameters in deploy message.

`143` - new validator reward fraction is greater than old.

`144` - new validator reward fraction is zero.

`146` - insufficient DePool balance.


Incorrect DePool function call by another contract:

`107` - message sender is not proxy contract.

`120` - message sender is not DePool (this is not a self call).

`125` - invalid confirmation from elector (invalid round step).

`126` - invalid confirmation from elector (invalid query ID).

`127` - invalid confirmation from elector (sender is not elector).
