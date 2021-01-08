#!/bin/bash
set -e
filename=MultiBallotDebot
filenamesol=$filename.sol
filenameabi=$filename.abi.json
filenametvc=$filename.tvc
filenamekeys=$filename.keys.json

function giver_local {
$CLI_PATH/tonos-cli call --abi $LOCAL_GIVER_PATH/giver.abi.json 0:841288ed3b55d9cdafa806807f02a0ae0c169aa5edfe88a789a6482429756a94 sendGrams "{\"dest\":\"$1\",\"amount\":5000000000}"
}
function giver_net {
$CLI_PATH/tonos-cli call 0:2bb4a0e8391e7ea8877f4825064924bd41ce110fce97e939d3323999e1efbb13 sendTransaction "{\"dest\":\"$1\",\"value\":2000000000,\"bounce\":\"false\"}" --abi $NET_GIVER_PATH/giver.abi.json --sign $NET_GIVER_PATH/keys.json
}
function get_address {
echo $(cat log.log | grep "Raw address:" | cut -d ' ' -f 3)    
}

echo ""
echo "[MULTIBALLOT DEBOT]"
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
sleep 1
echo DEPLOY DEBOT
debot_abi=$(cat $filenameabi | xxd -ps -c 20000)
target_abi=$(cat ../MultiBallot.abi | xxd -ps -c 20000)

$CLI_PATH/tonos-cli deploy $filenametvc "{\"options\":0,\"debotAbi\":\"\",\"targetAddr\":\"\",\"targetAbi\":\"\"}" --sign $filenamekeys --abi $filenameabi
echo SET DEBOT ABI
$CLI_PATH/tonos-cli call $debot_address setABI "{\"dabi\":\"$debot_abi\"}" --sign $filenamekeys --abi $filenameabi
echo SET TARGET ABI
$CLI_PATH/tonos-cli call $debot_address setTargetABI "{\"tabi\":\"$target_abi\"}" --sign $filenamekeys --abi $filenameabi
echo SET MSIG DEBOT ADDRESS
$CLI_PATH/tonos-cli call $debot_address setMsigDebot "{\"md\":\"$MSIG_DEBOT_ADDRESS\"}" --sign $filenamekeys --abi $filenameabi
echo SET MULTIBALOT
$CLI_PATH/tonos-cli call $debot_address setMbAbi "{\"dabi\":\"$target_abi\"}" --sign $filenamekeys --abi $filenameabi
echo SET SUPERROOT
sr_abi=$(cat ../SuperRoot.abi | xxd -ps -c 20000)
$CLI_PATH/tonos-cli call $debot_address setSrAbi "{\"dabi\":\"$sr_abi\"}" --sign $filenamekeys --abi $filenameabi
$CLI_PATH/tonos-cli call $debot_address setSrAddr "{\"addr\":\"$SUPER_ROOT_ADDRESS\"}" --sign $filenamekeys --abi $filenameabi
echo SET PROPOSALROOT
pr_abi=$(cat ../ProposalRoot.abi | xxd -ps -c 20000)
$CLI_PATH/tonos-cli call $debot_address setPrAbi "{\"dabi\":\"$pr_abi\"}" --sign $filenamekeys --abi $filenameabi

echo DONE
echo $debot_address > address.log

