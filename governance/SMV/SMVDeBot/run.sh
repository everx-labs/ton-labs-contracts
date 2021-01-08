#!/bin/bash
set -e
echo RUN DEBOT
debot_address=$(cat ./superRoot/address.log)
echo $debot_address
~/test/tonos-cli/target/release/tonos-cli debot fetch $debot_address


