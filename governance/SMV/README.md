# Working with SMV contracts

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
* run debots

## 2. TONOS-CLI Installation
### 2.1. Install TONOS-CLI and download contract files
#### Linux

Create a folder. Download the .tar.gz file from the latest release from here: https://github.com/tonlabs/tonos-cli/releases to this folder. Extract it:

```
tar -xvf tonos-cli_v0.1.27_linux.tar.gz
```
Download contract files (config.hpp, Budget.\*, Contest.\*, MultiBallot.\*, ProposalRoot.\*, SMVStats.\*, SuperRoot.\*) from https://github.com/tonlabs/ton-labs-contracts/tree/master/governance/SMV. Place them into the folder containing the TONOS-CLI executable.

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
Download contract files (config.hpp, Budget.\*, Contest.\*, MultiBallot.\*, ProposalRoot.\*, SMVStats.\*, SuperRoot.\*) from https://github.com/tonlabs/ton-labs-contracts/tree/master/governance/SMV. Place them into the tonos-cli/target/release/ utility folder.

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
TON-Compiler clang must be in PATH, check with `clang --version`:
`TON Labs clang for TVM. ... `

```
clang++ -o Budget.tvc Budget.cpp
clang++ -o MultiBallot.tvc MultiBallot.cpp
clang++ -o ProposalRoot.tvc ProposalRoot.cpp
clang++ -o SuperRoot.tvc SuperRoot.cpp
clang++ -o SMVStats.tvc SMVStats.cpp
clang++ -o Contest.tvc Contest.cpp
```
It will generate both tvc and abi files.
Also you may use pre-compiled tvc/abi files from the same repository, or use the provided Makefile for compilation.

## 5. Deploying super root to the Blockchain
### 5.1. Generating seed phrase
To generate your seed phrase enter the following command:
```
./tonos-cli genphrase
```
Terminal displays the generated seed phrase.
> Note: The seed phrase (and the corresponding key) is used only in deploy procedure of SuperRoot and will be zeroed when the contract is fully initialized.

### 5.2. Generating super root address and deployment key pair
1. Use the following command:
```
./tonos-cli getkeypair <deploy.keys.json> "<seed_phrase>"
```
`deploy.keys.json` - the file the key pair will be written to.
The utility generates the file that contains the key pair produced from seed phrase. Use it to generate your address:
```
./tonos-cli genaddr SuperRoot.tvc SuperRoot.abi --setkey deploy.keys.json --wc <workchain_id>
```
* `deploy.keys.json` - the file the key pair is read from.
* `--wc <workchain_id>` - (optional) ID of the workchain the contract will be deployed to (-1 for masterchain, 0 for basechain). By default this value is set to 0.
The utility displays the new super root address (Raw_address).

> Note: The super root address is required for any interactions with the contract.

It is better to save super root address into variable:
```
export TVM_SUPER_ROOT_ADDR=<super_root_address>
```

#### 5.2.1. (Optional) Check that a contract with the address generated on the previous step does not already exist in the blockchain
Request status for the generated contract address from the blockchain:
```
./tonos-cli account <super_root_address>
```
#### 5.2.2. Send a few tokens to the new address from another contract.
Create, and if necessary, confirm a transaction from some wallet.
Ensure that contract address has been created in the blockchain and has Uninit status.
```
./tonos-cli account <super_root_address>
```
### 5.3. Place ProposalRoot and MultiBallot code into variables
ProposalRoot and MultiBallot code must be set into SuperRoot after initial deploy (setProposalRootCode, setMultiBallotCode), so we need to save ProposalRoot.tvc and MultiBallot.tvc code into variables:
```
tvm_linker decode --tvc ProposalRoot.tvc > code_proposal.txt
tvm_linker decode --tvc MultiBallot.tvc > code_multiballot.txt
```
> Note: tvm_linker utility: https://github.com/tonlabs/TVM-linker

Edit code\_proposal.txt and code\_multiballot.txt to keep only `code: ` section content.
Save code\_proposal.txt and code\_multiballot.txt content into variables:
```
export TVM_PROPOSAL_CODE=`cat code_proposal.txt`
export TVM_MULTIBALLOT_CODE=`cat code_multiballot.txt`
```

### 5.4. Deploy the SMV budget and stats contracts
#### 5.4.1. Generate address of Budget and SMVStats
```
./tonos-cli genaddr Budget.tvc Budget.abi --setkey deploy.keys.json --wc <workchain_id>
./tonos-cli genaddr SMVStats.tvc SMVStats.abi --setkey deploy.keys.json --wc <workchain_id>
```
It is better to save Budget and SMVStats address into variables:
```
export TVM_BUDGET_ADDR=<budget_address>
export TVM_STATS_ADDR=<stats_address>
```
#### 5.4.2. (Optional) You may check that `<budget_address>` and `<stats_address>` are not yet occupied:
```
./tonos-cli account $TVM_BUDGET_ADDR
./tonos-cli account $TVM_STATS_ADDR
```
#### 5.4.3. Send a few tokens to the new addresses from another contract.
Create, and if necessary, confirm a transaction from some wallet.
Ensure that contract addresses have been created in the blockchain and has Uninit status.
```
./tonos-cli account $TVM_BUDGET_ADDR
./tonos-cli account $TVM_STATS_ADDR
```
#### 5.4.4. Run deploy commands for Budget and SMVStats contracts
You should provide calculated `<super_root_address>` as a constructor parameter `SMV_root`.
SMVStats contract will registrate statistic records from this address.
And Budget contract will process funds allocation requests (to an approved contest) from this address.
> Note: Do not transfer big funds to Budget contract until SuperRoot is deployed and fully initialized.

```
./tonos-cli deploy Budget.tvc '{"SMV_root":"'$TVM_SUPER_ROOT_ADDR'"}' --abi Budget.abi --sign deploy.keys.json --wc <workchain_id>
./tonos-cli deploy SMVStats.tvc '{"SMV_root":"'$TVM_SUPER_ROOT_ADDR'"}' --abi SMVStats.abi --sign deploy.keys.json --wc <workchain_id>
```

### 5.5. Deploy the super root contract to the blockchain
> Note: full deployment of the super root is splitted into three commands because the network has size limit for one message (16k) and the contracts (SuperRoot.tvc + ProposalRoot.tvc + MultiBallot.tvc) break this limit.

Use the following commands:
```
./tonos-cli deploy SuperRoot.tvc '{"budget":"'$TVM_BUDGET_ADDR'","stats":"'$TVM_STATS_ADDR'"}' --abi SuperRoot.abi --sign deploy.keys.json --wc <workchain_id>
```
Configuration parameters:
* `budget` - address of Budget contract.
* `stats` - address of SMVStats contract.
* `--wc <workchain_id>` - (optional) ID of the workchain the wallet will be deployed to (-1 for masterchain, 0 for basechain). By default this value is set to 0.

```
./tonos-cli call <super_root_address> setProposalRootCode '{"code":"'$TVM_PROPOSAL_CODE'"}' --abi SuperRoot.abi --sign deploy.keys.json
./tonos-cli call <super_root_address> setMultiBallotCode '{"code":"'$TVM_MULTIBALLOT_CODE'"}' --abi SuperRoot.abi --sign deploy.keys.json
```

#### 5.5.1. Check the super root status again
Now it should be Active.
```
./tonos-cli account <super_root_address>
```

#### 5.5.2. Check that the super root contract is fully initialized
```
./tonos-cli run <super_root_address> isFullyInitialized {} --abi SuperRoot.abi
```

## 6. Super Root requests
### 6.1. Selecting blockchain network

> Note: By default TONOS-CLI connects to net.ton.dev network.

Use the following command to switch to any other network 
```
./tonos-cli config --url <https://network_url>
```
You need to do it only once before using the utility.

A .json configuration file will be created in the TONOS-CLI utility folder. The URL of the current network will be specified there. All subsequent calls of the utility will use this file to select the network to connect to.

### 6.2. Creating of proposal
> Note: SuperRoot is not processing external commands after initialization. You need to prepare and send internal message from another contract (Multisig wallet, for example) to create multiballot or proposal.
```
bool_t createProposal(uint256 id, address depool, uint128 totalVotes,
                      uint32 startime, uint32 endtime, bytes desc,
                      bool_t superMajority, uint256 votePrice,
                      bool_t finalMsgEnabled,
                      cell finalMsg, uint256 finalMsgValue, uint256 finalMsgRequestValue,
                      bool_t whiteListEnabled, dict_array<uint256> whitePubkeys);
```
The internal call will return success flag with the rest of funds. The deployed proposal address may be known using `getProposalAddress` getter.

### 6.3. Creating of multiballot
#### 6.3.1 Calculating multiballot address for specified public key
```
./tonos-cli run <super_root_address> getMultiBallotAddress '{"pubkey":"0x<ballot public key>", "depool":"<depool address>"}' --abi SuperRoot.abi
```

#### 6.3.2 Deploying MultiBallot from super root
> Note: SuperRoot is not processing external commands after initialization. You need to prepare and send internal message from another contract (Multisig wallet, for example) to create multiballot or proposal.

```
address createMultiBallot(uint256 pubkey, address depool, uint256 tonsToBallot);
```
The internal call will return the deployed MultiBallot address with the rest of funds. The returned address should be equal to calculated by getWalletAddress.

## 7. It is recommended to use SMV DeBots for proposal/multiballot creation and voting.
### 7.1 Deploy SMV DeBot
DeBots should be deployed in the following order:
* SMVStatDebot
* ProposalRootDebot
* MultiBallotDebot
* SuperRootDebot
> Note: You can see `deployall.sh` script file for more details.
### 7.2 How to vote
#### 7.2.1 Deploy MultiBallot
To vote for proposals you need to have MultiBallot account(smart-contract). To deploy your  MultiBallot first of all you need seed phrase and keypair. You can use tonos-cli to generate it. Run command to generate seed phrase:
```./tonos-cli genphrase```
Than you can create a key pair file from a seed phrase using the following command:
```./tonos-cli getkeypair <keyfile.json> "<seed_phrase>"```
Now you can start deploy MultiBallot from SMV DeBot. Select command `3) Deploy MultiBallot`. Enter the address of the multisig wallet from which you want to pay for the deployment.  At second step you should enter your generated public key. And then enter the amount of tons you want to send to you MultiBallot as mainterance (1 ton will be fine). Select `1) Yes - let's deploy!` and submit transaction with you  multisig  seed phrase or keypair file. Now you  MultiBallot is deployed.
Select `1) Vote` and enter your MultiBallot public key. Now you need to make deposit. Select `4) Add deposit from msig` or `5) Add deposit from depool` and follow instructions. You allways can check you deposit with `3) Get total deposit` command. You can withdraw you deposit with command `6) Withdraw deposit`. 
> Note: you cannot withdraw your deposit until all proposals you voted for have been completed
#### 7.2.2 Vote
Select `1) Vote`command from SMV DeBot. Enter your MultiBallot public key and run `1) Vote` command to see all proposals you can vote and then vote for them.
If you know the specific proposal address you can vote for it with `2) Vote by proposal address` command.
### 7.3 Other commands
* To see information about budget transfers use command  `4) Show statistic`.
* You can use command `2) Deploy proposal` for deploy the proposal. 
* Some additional information can be obtain from `5) Additional information` command:
`1) Get proposal ids` - show the list of created proposals id.
`2) Get proposal address by id` – get the proposal address by its id.
`3) Get multiballot address` -  get the multiballot address by its public key
`4) Show proposal info` – show proposal info by the proposal address
