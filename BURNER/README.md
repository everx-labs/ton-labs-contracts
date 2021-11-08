# BURNER address in mainnet

0:3f078d3b7e22c8944e5561909a236ae48b48a7ea42f28dd861c22b6f64d7e97b

# How to build BurnerDeployer

## Prereq

solc 0.51.0
tvm_linker 0.13.83

## Compile

```bash
tondev sol compile BurnerDeployer.sol
```

# How to deploy Burner

## 1) Generate address for `BurnerDeployer`:

```bash
tonos-cli genaddr BurnerDeployer.tvc BurnerDeployer.abi.json --genkey BurnerDeployer.keys.json
```
## 2) Send 1 token to generated address.

## 3) Deploy `BurnerDeployer`:

```bash
tonos-cli deploy BurnerDeployer.tvc {} --abi BurnerDeployer.abi.json --sign BurnerDeployer.keys.json
```

## 4) call `deploy` function:

```bash
tonos-cli call <deployer_address> deploy {} --abi BurnerDeployer.abi.json --sign BurnerDeployer.keys.json
```
<deployer_address> - insert here address of the deployer.
