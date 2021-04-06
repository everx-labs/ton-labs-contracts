# How to create DeBot derived from your smart contract

## Prepare initial ReDeNS files

You need redens.tvc, redens.abi.json, debots.key.json.

Also you need `tonos-cli` >= 0.11.0 version.

## Generate author seed phrase

    tonos-cli genphrase

Important: dont forget or loose the phrase. It is needed to upgrade ReDeNS to real DeBot.

## Get author public key

    tonos-cli genpubkey "author seed phrase"

`author seed phrase` - the seed phrase generated at previous step.

## Prepare ReDeNS Image

Copy and rename the original certificate image:

    cp redens.tvc redens<DebotName>.tvc

`DebotName` - name of you DeBot. Example:

    cp redens.tvc redensDePool.tvc

Generate ReDeNS address and update image file:

    tonos-cli genaddr redens<DeBotName>.tvc redens.abi.json --setkey debots.key.json --data '{"codeHash":"<codeHashOfYourSmartContract>"}' --wc 0 --save

`codeHashOfYourSmartContract` - insert here code hash of your smart contract starting with `0x`.

redens<DeBotName>.tvc file will be rewritten.

Remember `Raw address` printed to the terminal. It is the address of your DeBot.

## Deploy ReDeNS to blockchain

Send 2 tons to the address generated at previous step.

Deploy image using cli:

    tonos-cli deploy redens<DeBotName>.tvc '{"pubkey":"<authorPublicKey>"}' --abi redens.abi.json --sign "author seed phrase"

`authorPublicKey` - insert here the author public key starting with `0x`.


## Upgrade ReDeNS to real DeBot

Run `update.sh` script:

    update.sh <address> <DeBotFileName>

`address` - Free TON address of Reverse DeBot Certificate.
`DeBotFileName` - the name of DeBot used as prefix for tvc and abi.json files. For example, if name is `msigDebot` then script will try to read `msigDebot.tvc` and `msigDebot.abi.json` files.

