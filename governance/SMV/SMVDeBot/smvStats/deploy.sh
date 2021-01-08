#!/bin/bash
set -e
filename=smvStatDebot
filenamesol=$filename.sol
filenameabi=$filename.abi.json
filenametvc=$filename.tvc
filenamekeys=$filename.keys.json

function giver_local {
$CLI_PATH/tonos-cli call --abi $LOCAL_GIVER_PATH/giver.abi.json 0:841288ed3b55d9cdafa806807f02a0ae0c169aa5edfe88a789a6482429756a94 sendGrams "{\"dest\":\"$1\",\"amount\":1000000000}"
}
function giver_net {
$CLI_PATH/tonos-cli call 0:2bb4a0e8391e7ea8877f4825064924bd41ce110fce97e939d3323999e1efbb13 sendTransaction "{\"dest\":\"$1\",\"value\":1000000000,\"bounce\":\"false\"}" --abi $NET_GIVER_PATH/giver.abi.json --sign $NET_GIVER_PATH/keys.json
}
function get_address {
echo $(cat log.log | grep "Raw address:" | cut -d ' ' -f 3)    
}

echo ""
echo "[SMVSTAT DEBOT]"
echo ""

echo GENADDR DEBOT
$CLI_PATH/tonos-cli genaddr $filenametvc $filenameabi --genkey $filenamekeys > log.log
debot_address=$(get_address)
echo GIVER
if [ "$DEPLOY_LOCAL" = "" ]; then
giver_net $debot_address
else
giver_local $debot_address
fi
echo DEPLOY DEBOT
debot_abi=$(cat $filenameabi | xxd -ps -c 20000)
target_abi=$(cat ../SMVStats.abi | xxd -ps -c 20000)

$CLI_PATH/tonos-cli deploy $filenametvc "{\"options\":4,\"debotAbi\":\"\",\"targetAddr\":\"$SMV_STAT_ADDRESS\",\"targetAbi\":\"\"}" --sign $filenamekeys --abi $filenameabi
echo SET DEBOT ABI
$CLI_PATH/tonos-cli call $debot_address setABI "{\"dabi\":\"$debot_abi\"}" --sign $filenamekeys --abi $filenameabi
echo SET TARGET ABI
$CLI_PATH/tonos-cli call $debot_address setTargetABI "{\"tabi\":\"$target_abi\"}" --sign $filenamekeys --abi $filenameabi


echo DONE
echo $debot_address > address.log

