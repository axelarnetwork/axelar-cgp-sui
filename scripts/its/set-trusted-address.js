require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { publishInterchainToken } = require('./publish-interchain-token');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const {BCS, getSuiMoveConfig} = require("@mysten/bcs");

const testInfo = require('../../info/test.json');
const { registerInterchainToken } = require('./register-token');
const { arrayify } = require('ethers/lib/utils');

async function setTrustedAddress(client, keypair, testInfo, chainName, trustedAddress) {
    const itsPackageId = testInfo.packageId;
    const itsObjectId = testInfo['its::ITS'].objectId;

    let tx = new TransactionBlock();

    tx.moveCall({
        target: `${itsPackageId}::storage::set_trusted_address`,
        arguments: [
            tx.object(itsObjectId),
            tx.pure.string(chainName),
            tx.pure.string(trustedAddress),
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

        await setTrustedAddress(client, keypair, testInfo[env], chainName, trustedAddress);
    })();
}