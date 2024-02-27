require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { MIST_PER_SUI } = require('@mysten/sui.js/utils');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { execSync } = require('child_process');
const fs = require('fs');
const tmp = require('tmp');
const { publishPackageFull } = require('./publish-package');
const { getConfig, setConfig, getFullObject } = require('./utils');

async function publishAll(client, keypair, env) {
    const upgradeCaps = {};
    const packageIds = {};
    for(const packagePath of ['axelar', 'governance', 'gas_service', 'its']) {
        console.log(packagePath);
        const { packageId, publishTxn } = await publishPackageFull(packagePath, client, keypair, env);
        upgradeCaps[packagePath] =  publishTxn.objectChanges.find((obj) => obj.objectType == '0x2::package::UpgradeCap' );
        packageIds[packagePath] = packageId;
    }

    let tx = new TransactionBlock();
    tx.moveCall({   
            target: `${packageIds['governance']}::governance::new`,
        arguments: [
            tx.pure.string('Axelar'),
            tx.pure.string('the governance source addresss'),
            tx.pure.u256(0),
            tx.object(upgradeCaps['governance']['objectId']),
        ],
        typeArguments: [],
    });
    const publishTxn = await client.signAndExecuteTransactionBlock({
		transactionBlock: tx,
		signer: keypair,
		options: {
			showEffects: true,
			showObjectChanges: true,
            showContent: true
		},
	});

    const governance = publishTxn.objectChanges.find((obj) => obj.objectType == `${packageIds['governance']}::governance::Governance`);

    const governanceConfig = getConfig('governance', env.alias);

    governanceConfig['governance::Governance'] = await getFullObject(governance, client);

    setConfig('governance', env.alias, governanceConfig);

    tx = new TransactionBlock();
    for(const packagePath of ['axelar', 'gas_service', 'its']) {
        console.log(packagePath);
        tx.moveCall({   
                target: `${packageIds['governance']}::governance::take_upgrade_cap`,
            arguments: [
                tx.object(governance.objectId),
                tx.object(upgradeCaps[packagePath]['objectId']),
            ],
            typeArguments: [],
        });
    }

    console.log(await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showContent: true
        },
    }));
}

if (require.main === module) {
    const env = ((arg) => {
        switch (arg?.toLowerCase()) {
            case 'localnet':
            case 'devnet':
            case 'testnet':
            case 'mainnet':
                return {alias: arg, url: getFullnodeUrl(arg)};
            default:
                return JSON.parse(arg);
      }
    })(process.argv[2] || 'localnet');
    const faucet = (process.argv[3]?.toLowerCase?.() === 'true');
    
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
        await publishAll(client, keypair, env);
    })();
}