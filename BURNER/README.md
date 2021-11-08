# Prereq

solc 0.51.0
tvm_linker 0.13.83

# How to build BurnerDeployer

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
