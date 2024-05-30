require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { SuiClient } = require('@mysten/sui.js/client');
const { getConfig } = require('../utils');
async function setSquidDiscovery(client, keypair, env) {
    const squid_info = getConfig('squid', env.alias);
    const itsId = getConfig('its', env.alias)['its::ITS'].objectId;
    const relayerDiscoveryId = getConfig('axelar', env.alias)['discovery::RelayerDiscovery'].objectId;
    const tx = new TransactionBlock();
    console.log(squid_info['squid::Squid'].objectId, itsId, relayerDiscoveryId);
    tx.moveCall({
        target: `${squid_info.packageId}::discovery::register_transaction`,
        arguments: [tx.object(squid_info['squid::Squid'].objectId), tx.object(itsId), tx.object(relayerDiscoveryId)],
        type_arguments: [],
    });

    await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForLocalExecution',
    });
}

module.exports = {
    setSquidDiscovery,
};

if (require.main === module) {
    const env = process.argv[2] || 'localnet';

    (async () => {
        const privKey = Buffer.from(process.env.SUI_PRIVATE_KEY, 'hex');
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

        await setSquidDiscovery(client, keypair, env);
    })();
}
