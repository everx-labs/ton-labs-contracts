#!/bin/sh
set -e
echo "Recompile contracts..."
/o/projects/broxus/elector/sold --version
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
        /o/projects/broxus/elector/sold $src.tsol
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
        echo "Done $src.tsol"
    fi
done
cd ..
mv rebuild/* binaries/
rm -rf rebuild
echo "Run tests..."
python test_elector.py
