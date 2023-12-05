require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { MIST_PER_SUI } = require('@mysten/sui.js/utils');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { execSync } = require('child_process');
const fs = require('fs');
const tmp = require('tmp');


const { getModuleNameFromSymbol } = require('./utils');
const { updateMoveToml, publishPackage } = require('./publish-package');

const packagePath = 'interchain_token';

async function publishInterchainToken(client, keypair, symbol, decimals, itsPackageId, itsObjectId) {
    let file = fs.readFileSync(`scripts/interchain_token.move`, 'utf8');
    let moduleName = getModuleNameFromSymbol(symbol);
    let witness = moduleName.toUpperCase();
    file = file.replaceAll('$module_name', moduleName);
    file = file.replaceAll('$witness', witness);
    file = file.replaceAll('$decimals', decimals);
    fs.writeFileSync(`move/${packagePath}/sources/interchain_token.move`, file);

    const { packageId, publishTxn } = await publishPackage(`../move/${packagePath}`, client, keypair);
    
    const treasuryCap = publishTxn.objectChanges.find(object => {
        return object.objectType && object.objectType.startsWith('0x2::coin::TreasuryCap');
    });
    const coinMetadata = publishTxn.objectChanges.find(object => {
        return object.objectType && object.objectType.startsWith('0x2::coin::CoinMetadata');
    });

    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${itsPackageId}::service::give_unregistered_coin`,
        arguments: [
            tx.object(itsPackageId),
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
	});

}

if (require.main === module) {
    const symbol = process.argv[2] || 'TT';
    const decimals = process.argv[3] || 6;
    const env = process.argv[4] || 'localnet';
    
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

        const its = require('../info/test.json');
        const itsPackageId = its[env].packageId;
        const itsObjectId = its[env]['storage::ITS'].objectId;

        publishInterchainToken(client, keypair, symbol, decimals, itsPackageId, itsObjectId);
    })();
}