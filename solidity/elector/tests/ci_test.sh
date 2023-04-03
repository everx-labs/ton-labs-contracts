#!/bin/sh
set -e

# echo install linux components
# apt-get update && apt-get install -y python3 python3-pip jq

echo install python modules
pip install -r requirements.txt
echo "Recompile contracts..."
sold --version
rm -rf rebuild
mkdir rebuild
cp ../*sol rebuild/
sed '/pragma ton-solidity/a pragma upgrade func;' rebuild/Config.sol > rebuild/Config.Update.sol
sed '/pragma ton-solidity/a pragma upgrade func;' rebuild/Elector.sol > rebuild/Elector.Update.sol
cd rebuild
for src in $(ls [!I]*.sol | sed -E 's/\.sol//g')
do
    if [ "$src" != "Common" ]
    then
        echo
        echo "Process file $src.sol ..."
        sold $src.sol
        dbg=$src.debug.json
        if jq -e '.map' $dbg > /dev/null
        then
            jq '.map' $dbg > temp.json
            mv temp.json $dbg
        fi
    fi
done
cd ..
mv rebuild/* binaries/
rm -rf rebuild
echo "Run tests..."
python3 test_elector.py
