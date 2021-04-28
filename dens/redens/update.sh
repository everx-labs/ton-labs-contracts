#!/bin/bash
set -e
tos=./tonos-cli
if test -f "$tos"; then
    echo "$tos exists."
else
    echo "$tos not found in current directory. Please, copy it here and rerun script."
    exit
fi

debot=$1
debot_name=$2
debot_abi=$(cat $debot_name.abi.json | xxd -ps -c 20000)
new_state=$( base64 -w 0 $debot_name.tvc)
signer=$3

echo "{\"state\":\"$new_state\"}" > upgrade.txt
$tos call $debot upgrade upgrade.txt --sign "$signer" --abi $debot_name.abi.json
$tos call $debot setABI "{\"dabi\":\"$debot_abi\"}" --sign "$signer" --abi $debot_name.abi.json
rm upgrade.txt
echo DONE