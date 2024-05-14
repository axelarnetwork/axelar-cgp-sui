require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const fs = require('fs');

const { getModuleNameFromSymbol, getConfig } = require('../utils');
const { publishPackage } = require('../publish-package');

const packagePath = 'interchain_token';

async function publishInterchainToken(client, keypair, itsInfo, name, symbol, decimals, skipRegister = false) {

    let file = fs.readFileSync(`scripts/its/interchain_token.move`, 'utf8');
    let moduleName = getModuleNameFromSymbol(symbol);
    let witness = moduleName.toUpperCase();
    file = file.replaceAll('$module_name', moduleName);
    file = file.replaceAll('$witness', witness);
    file = file.replaceAll('$name', name);
    file = file.replaceAll('$symbol', symbol);
    file = file.replaceAll('$decimals', decimals);
    fs.writeFileSync(`move/${packagePath}/sources/interchain_token.move`, file);

    const { packageId, publishTxn } = await publishPackage(`../move/${packagePath}`, client, keypair);
    
    const treasuryCap = publishTxn.objectChanges.find(object => {
        return object.objectType && object.objectType.startsWith('0x2::coin::TreasuryCap');
    });
    const coinMetadata = publishTxn.objectChanges.find(object => {
        return object.objectType && object.objectType.startsWith('0x2::coin::CoinMetadata');
    });

    coinType = `${packageId}::${moduleName}::${witness}`;

    if(skipRegister) {
        return { 
            coinType, 
            treasuryCap, 
            coinMetadata 
        };
    }
    
    const itsPackageId = itsInfo.packageId;
    const itsObjectId = itsInfo['its::ITS'].objectId;

    const tx = new TransactionBlock();
    
    tx.moveCall({
        target: `${itsPackageId}::service::give_unregistered_coin`,
        arguments: [
            tx.object(itsObjectId),
            tx.object(treasuryCap.objectId),
            tx.object(coinMetadata.objectId),
        ],
        typeArguments: [`${packageId}::${moduleName}::${witness}`],
    });

    await client.signAndExecuteTransactionBlock({
		transactionBlock: tx,
		signer: keypair,
		options: {
			showEffects: true,
			showObjectChanges: true,
            showContent: true
		},
        requestType: 'WaitForEffectsCert',
	});

    return {
        coinType
    }
}

module.exports = {
    publishInterchainToken,
}

if (require.main === module) {
    const symbol = process.argv[2] || 'TT';
    const decimals = process.argv[3] || 6;
    const skipRegister = process.argv[4] ? process.argv[4] != 'false' : false;
    const env = process.argv[5] || 'localnet';
    
    (async () => {
        const privKey = 
        Buffer.from(
            process.env.SUI_PRIVATE_KEY,
            "hex"
        );
        const keypair = Ed25519Keypair.fromSecretKey(privKey);
        const address = keypair.getPublicKey().toSuiAddress();
        // create a new SuiClient object pointing to the network you want to use
        const client = new SuiClient({ url: getFullnodeUrl(env) });

        try {
            await requestSuiFromFaucetV0({
            // use getFaucetHost to make sure you're using correct faucet address
            // you can also just use the address (see Sui Typescript SDK Quick Start for values)
            host: getFaucetHost(env),
            recipient: address,
            });
        } catch (e) {
            console.log(e);
        }
        await publishInterchainToken(client, keypair, getConfig('its', env), '', symbol, decimals, skipRegister);
    })();
}