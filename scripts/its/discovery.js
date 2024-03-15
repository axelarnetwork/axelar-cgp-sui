require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');

const { getConfig } = require('../utils');

async function setItsDiscovery(client, keypair, axelarInfo, testInfo) {
    const itsPackageId = testInfo.packageId;
    const itsObjectId = testInfo['its::ITS'].objectId;
    const relayerDecovery = axelarInfo['discovery::RelayerDiscovery'].objectId;

    let tx = new TransactionBlock();

    tx.moveCall({
        target: `${itsPackageId}::discovery::register_transaction`,
        arguments: [
            tx.object(itsObjectId),
            tx.object(relayerDecovery),
        ],
        typeArguments: [],
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

module.exports = {
    setItsDiscovery,
}


if (require.main === module) {
    const env = process.argv[2] || 'localnet';
    const chainName = process.argv[3] || 'Ethereum';
    const trustedAddress = process.argv[4] || '0x1234';
    
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

        await setItsDiscovery(client, keypair, getConfig('axelar', env), getConfig('its', env));
    })();
}