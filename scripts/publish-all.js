require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { publishPackageFull } = require('./publish-package');
const { initializeGovernance, takeUpgradeCaps } = require('./governance');

async function publishAll(client, keypair, env) {
    const upgradeCaps = {};
    const packageIds = {};
    for(const packagePath of ['abi', 'axelar', 'governance', 'gas_service', 'its']) {
        console.log(packagePath);
        while (true) try {
            const { packageId, publishTxn } = await publishPackageFull(packagePath, client, keypair, env);
            upgradeCaps[packagePath] =  publishTxn.objectChanges.find((obj) => obj.objectType == '0x2::package::UpgradeCap' );
            packageIds[packagePath] = packageId;
            break;
        } catch(e) {
            console.log(e);
            console.log(`Retrying for ${packagePath}`);
        }
    }

    await initializeGovernance(upgradeCaps.governance, client, keypair, env);

    await takeUpgradeCaps(
        ['abi', 'axelar', 'gas_service', 'its'].map(packagePath => upgradeCaps[packagePath]),
        client,
        keypair,
        env,
    );
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