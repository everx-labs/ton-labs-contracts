#!/bin/bash
set -e

$LINKER_PATH/tvm_linker compile BURNER.code --abi-json BURNER.abi.json --data data.boc -o BURNER.tvc