require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');


const { getModuleNameFromSymbol } = require('./utils');
const { updateMoveToml, publishPackage } = require('./publish-package');
const { keccak256, toUtf8Bytes, hexlify } = require('ethers/lib/utils');

const packagePath = 'interchain_token';

async function getUnregisteredToken(client, keypair, symbol, decimals, itsPackageId, itsObjectId) {
    const tx = new TransactionBlock();
    tx.moveCall({
        target: `${itsPackageId}::storage::get_unregistered_coin_type`,
        arguments: [
            tx.object(itsObjectId),
            tx.pure.string(symbol),
            tx.pure.u8(decimals),
        ]
    });
    resp = await client.devInspectTransactionBlock({
        sender: keypair.getPublicKey().toSuiAddress(),
        transactionBlock: tx,
    });

    console.log(String.fromCharCode(...resp.results[0].returnValues[0][0]));
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
        const itsObjectId = its[env]['its::ITS'].objectId;

        await getUnregisteredToken(client, keypair, symbol, decimals, itsPackageId, itsObjectId);
    })();
}
