require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { execSync } = require('child_process');
const fs = require('fs');
const tmp = require('tmp');
const { setConfig, getFullObject } = require('./utils');
const { parseEnv } = require('./utils');

async function publishPackage(packagePath, client, keypair) {
	// remove all controlled temporary objects on process exit
    const address = keypair.getPublicKey().toSuiAddress();
	tmp.setGracefulCleanup();

	const tmpobj = tmp.dirSync({ unsafeCleanup: true });
    
	const { modules, dependencies } = JSON.parse(
		execSync(
			`sui move build --dump-bytecode-as-base64 --path ${__dirname + '/../move/' + packagePath} --install-dir ${tmpobj.name}`,
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
    const coins = await client.getCoins({owner: address});
    tx.setGasPayment(coins.data.map(coin => {
        coin.objectId = coin.coinObjectId; 
        return coin;
    }));

	const publishTxn = await client.signAndExecuteTransactionBlock({
		transactionBlock: tx,
		signer: keypair,
		options: {
			showEffects: true,
			showObjectChanges: true,
            showContent: true
		},
	});
	if(publishTxn.effects?.status.status != 'success') throw new Error('Publish Tx failed');

	const id = ((publishTxn.objectChanges?.filter(
		(a) => a.type === 'published',
	)) ?? [])[0].packageId.replace(/^(0x)(0+)/, '0x');

 	// package ID must have 64 characters even if first digit is less than #A
 	const packageId = id.length === 65 ? id.replace('0x', '0x0') : id;

	console.info(`Published package ${packageId} from address ${address}}`);

	return { packageId, publishTxn };
}

function updateMoveToml(packagePath, packageId) {
    const path = `${__dirname}/../move/${packagePath}/Move.toml`;
    const toml = fs.readFileSync(path, 'utf8');
    fs.writeFileSync(path, fillAddresses(insertPublishedAt(toml, packageId), packageId));
}

function insertPublishedAt(toml, packageId) {
    const lines = toml.split('\n');
    const versionLineIndex = lines.findIndex(line => line.slice(0, 7) === 'version');
    if(! (lines[versionLineIndex + 1].slice(0, 12) === 'published-at')) {
        lines.splice(versionLineIndex + 1, 0, '');
    }
    lines[versionLineIndex + 1] = `published-at = "${packageId}"`;
    return lines.join('\n');
}

function fillAddresses(toml, address) {
    const lines = toml.split('\n');
    const addressesIndex = lines.findIndex(line => line.slice(0, 11) === '[addresses]');
    for(let i = addressesIndex + 1; i<lines.length; i++) {
        const line = lines[i];
        const eqIndex = line.indexOf('=');
        lines[i] = line.slice(0, eqIndex+1) + ` "${address}"`;
    }
    return lines.join('\n');
}

async function publishPackageFull(packagePath, client, keypair, env) {
    let toml = fs.readFileSync(`${__dirname}/../move/${packagePath}/Move.toml`, 'utf8');
    fs.writeFileSync(`${__dirname}/../move/${packagePath}/Move.toml`, fillAddresses(toml, '0x0'));

    const { packageId, publishTxn } = await publishPackage(packagePath, client, keypair);
    const info = require(`${__dirname}/../move/${packagePath}/info.json`);
    const config = {};
    config.packageId = packageId;
    for(const singleton of info.singletons) {
        const object = publishTxn.objectChanges.find(object => (object.objectType === `${packageId}::${singleton}`));
        config[singleton] = await getFullObject(object, client);
    }
    
    setConfig(packagePath, env.alias, config);
    updateMoveToml(packagePath, packageId);

    return {packageId, publishTxn};
}

module.exports = {
    publishPackage,
    updateMoveToml,
    publishPackageFull,
}


if (require.main === module) {
    const packagePath = process.argv[2] || 'axelar';
    const env = parseEnv(process.argv[3] || 'localnet');
    const faucet = (process.argv[4]?.toLowerCase?.() === 'true');
    
    (async () => {
        const privKey = 
        Buffer.from(
            process.env.SUI_PRIVATE_KEY,
            "hex"
        );
        const keypair = Ed25519Keypair.fromSecretKey(privKey);
        const address = keypair.getPublicKey().toSuiAddress();
        // create a new SuiClient object pointing to the network you want to use
        const client = new SuiClient({ url: env.url });

        if (faucet) {
            try {
                await requestSuiFromFaucetV0({
                // use getFaucetHost to make sure you're using correct faucet address
                // you can also just use the address (see Sui Typescript SDK Quick Start for values)
                host: getFaucetHost(env.alias),
                recipient: address,
                });
            } catch (e) {
                console.log(e);
            }
        }

        await publishPackageFull(packagePath, client, keypair, env);
    })();
}