require('dotenv').config();
const { requestSuiFromFaucet, updateMoveToml } = require('./utils');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { SuiClient } = require('@mysten/sui.js/client');
const { execSync } = require('child_process');
const { parseEnv } = require('./utils');
const tmp = require('tmp');
const path = require('path');

async function publishPackage(packageName, client, keypair) {
    updateMoveToml(packageName, '0x0');

    // remove all controlled temporary objects on process exit
    const address = keypair.getPublicKey().toSuiAddress();
    tmp.setGracefulCleanup();

    const tmpobj = tmp.dirSync({ unsafeCleanup: true });

    const { modules, dependencies } = JSON.parse(
        execSync(
            `sui move build --dump-bytecode-as-base64 --path ${path.join(__dirname, '/../move/', packageName)} --install-dir ${
                tmpobj.name
            }`,
            {
                encoding: 'utf-8',
                stdio: 'pipe', // silent the output
            },
        ),
    );

    const tx = new TransactionBlock();
    const cap = tx.publish({
        modules,
        dependencies,
    });

    // Transfer the upgrade capability to the sender so they can upgrade the package later if they want.
    tx.transferObjects([cap], tx.pure(address));

    const publishTxn = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showContent: true,
        },
    });
    if (publishTxn.effects?.status.status !== 'success') throw new Error('Publish Tx failed');

    const packageId = (publishTxn.objectChanges?.filter((a) => a.type === 'published') ?? [])[0].packageId;

    console.info(`Published package ${packageId} from address ${address}}`);

    updateMoveToml(packageName, packageId);

    return { packageId, publishTxn };
}

module.exports = {
    publishPackage,
};

if (require.main === module) {
    const packageName = process.argv[2] || 'axelar';
    const env = parseEnv(process.argv[3] || 'localnet');
    const faucet = process.argv[4]?.toLowerCase?.() === 'true';

    (async () => {
        const privKey = Buffer.from(process.env.SUI_PRIVATE_KEY, 'hex');
        const keypair = Ed25519Keypair.fromSecretKey(privKey);
        const address = keypair.getPublicKey().toSuiAddress();
        // create a new SuiClient object pointing to the network you want to use
        const client = new SuiClient({ url: env.url });

        if (faucet) {
            await requestSuiFromFaucet(env, address);
        }

        await publishPackage(packageName, client, keypair, env);
    })();
}
