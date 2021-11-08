# BURNER 

Address in mainnet:

    -1:efd5a14409a8a129686114fc092525fddd508f1ea56d1b649a3a695d3a5b188c

NOTE1: The Burner smc is very simple, so it does not have ABI interface.

Burner contains empty data and only 2 tvm instructions in the code: 

```bash
SETCP0 
NOP
```

Important: The Burner does not have any owner or keys.

### How to check that Burner has no keys.

1. Dump and decode the Burner state with the following command:

```bash
tonos-cli -u main.ton.dev decode stateinit -1:efd5a14409a8a129686114fc092525fddd508f1ea56d1b649a3a695d3a5b188c
```

2. Then deserialize `data` with:

```bash
echo -n <insert base64 data field here> | base64 -d | xxd
```

Example: 

```bash
echo -n te6ccgEBAQEAAgAAAA== | base64 -d | xxd
00000000: b5ee 9c72 0101 0101 0002 0000 00         ...r.........
```

First 13 bytes is a boc header after which there is no data bytes, it means that there is no public key.

### Another way to check Burner data using tvm_linker

```bash
tonos-cli -u main.ton.dev account -1:efd5a14409a8a129686114fc092525fddd508f1ea56d1b649a3a695d3a5b188c --dumptvc acc.tvc
tvm_linker disasm dump acc.tvc

```

Example of tvm_linker output:

```bash
$ tvm_linker disasm dump acc.tvc
└ ff0000
```

Decoded Burner stateInit contains only the code cell with 2 instructions (ff00 - SETCP0, 00 - NOP) and no data cell.

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
