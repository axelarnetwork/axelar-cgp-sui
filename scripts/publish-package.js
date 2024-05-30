require('dotenv').config();
const { setConfig, getFullObject, requestSuiFromFaucet } = require('./utils');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { SuiClient } = require('@mysten/sui.js/client');
const { execSync } = require('child_process');
const { parseEnv } = require('./utils');
const tmp = require('tmp');
const fs = require('fs');

async function publishPackage(packageName, client, keypair) {
    const toml = fs.readFileSync(`${__dirname}/../move/${packageName}/Move.toml`, 'utf8');
    fs.writeFileSync(`${__dirname}/../move/${packageName}/Move.toml`, fillAddresses(toml, '0x0', packageName));

    // remove all controlled temporary objects on process exit
    const address = keypair.getPublicKey().toSuiAddress();
    tmp.setGracefulCleanup();

    const tmpobj = tmp.dirSync({ unsafeCleanup: true });

    const { modules, dependencies } = JSON.parse(
        execSync(`sui move build --dump-bytecode-as-base64 --path ${__dirname + '/../move/' + packageName} --install-dir ${tmpobj.name}`, {
            encoding: 'utf-8',
            stdio: 'pipe', // silent the output
        }),
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
        requestType: 'WaitForLocalExecution',
    });
    if (publishTxn.effects?.status.status != 'success') throw new Error('Publish Tx failed');

    const packageId = (publishTxn.objectChanges?.filter((a) => a.type === 'published') ?? [])[0].packageId;

    console.info(`Published package ${packageId} from address ${address}}`);

    return { packageId, publishTxn };
}

function updateMoveToml(packageName, packageId) {
    const path = `${__dirname}/../move/${packageName}/Move.toml`;
    const toml = fs.readFileSync(path, 'utf8');
    fs.writeFileSync(path, fillAddresses(insertPublishedAt(toml, packageId), packageId, packageName));
}

function insertPublishedAt(toml, packageId) {
    const lines = toml.split('\n');
    const versionLineIndex = lines.findIndex((line) => line.slice(0, 7) === 'version');

    if (!(lines[versionLineIndex + 1].slice(0, 12) === 'published-at')) {
        lines.splice(versionLineIndex + 1, 0, '');
    }

    lines[versionLineIndex + 1] = `published-at = "${packageId}"`;
    return lines.join('\n');
}

function fillAddresses(toml, address, packageName) {
    const lines = toml.split('\n');
    const addressesIndex = lines.findIndex((line) => line.slice(0, 11) === '[addresses]');

    for (let i = addressesIndex + 1; i < lines.length; i++) {
        const line = lines[i];
        const eqIndex = line.indexOf('=');

        if (eqIndex < 0 || line.slice(0, eqIndex - 1) !== packageName) {
            continue;
        }

        lines[i] = line.slice(0, eqIndex + 1) + ` "${address}"`;
    }

    return lines.join('\n');
}

async function publishPackageFull(packageName, client, keypair, env) {
    const { packageId, publishTxn } = await publishPackage(packageName, client, keypair);
    const info = require(`${__dirname}/../move/${packageName}/info.json`);
    const config = {};
    config.packageId = packageId;

    for (const singleton of info.singletons) {
        const object = publishTxn.objectChanges.find((object) => object.objectType === `${packageId}::${singleton}`);
        config[singleton] = await getFullObject(object, client);
    }

    setConfig(packageName, env.alias, config);
    updateMoveToml(packageName, packageId);

    return { packageId, publishTxn };
}

module.exports = {
    publishPackage,
    updateMoveToml,
    publishPackageFull,
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

        await publishPackageFull(packageName, client, keypair, env);
    })();
}
