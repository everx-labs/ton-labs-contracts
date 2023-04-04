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
cp ../*tsol rebuild/
sed '/pragma ton-solidity/a pragma upgrade func;' rebuild/Config.tsol > rebuild/Config.Update.tsol
sed '/pragma ton-solidity/a pragma upgrade func;' rebuild/Elector.tsol > rebuild/Elector.Update.tsol
cd rebuild
for src in $(ls [!I]*.tsol | sed -E 's/\.tsol//g')
do
    if [ "$src" != "Common" ]
    then
        echo
        echo "Process file $src.tsol ..."
        sold $src.tsol
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
python test_elector.py
