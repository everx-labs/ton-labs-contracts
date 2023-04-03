#!/bin/sh
set -e
echo "Recompile contracts..."
/o/projects/broxus/elector/sold --version
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
        /o/projects/broxus/elector/sold $src.sol
        # dbg=$src.debug.json
        # map=$(jq -e '.map' $dbg)
        # if "$map" != "null"
        # then
        #     echo $map > $dbg
        # fi

        # if jq -e '.map' $dbg > /dev/null
        # then
        #     jq '.map | . +' $dbg > temp.json
        #     mv temp.json $dbg
        # fi
        echo "Done $src.sol"
    fi
done
cd ..
mv rebuild/* binaries/
rm -rf rebuild
echo "Run tests..."
python test_elector.py
