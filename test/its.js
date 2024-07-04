const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { publishPackage, getRandomBytes32 } = require('./utils');

const { arrayify } = require('ethers/lib/utils');
const { deployGateway } = require('./axelar-gateway');

async function deployIts(client, keypair) {
    await deployGateway(client, keypair);
    await publishPackage(client, keypair, 'abi');
    await publishPackage(client, keypair, 'governance');
    const result = await publishPackage(client, keypair, 'its');

    return result;
}

describe('test', () => {
    let client;
    const operator = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const deployer = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const keypair = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    let packageId;
    let its;

    before(async () => {
        client = new SuiClient({ url: getFullnodeUrl('localnet') });

        await Promise.all(
            [operator, deployer, keypair].map((keypair) =>
                requestSuiFromFaucetV0({
                    host: getFaucetHost('localnet'),
                    recipient: keypair.toSuiAddress(),
                }),
            ),
        );

        const result = await deployIts(client, deployer);

        packageId = result.packageId;
        its = result.publishTxn.objectChanges.find((change) => change.objectType === `${packageId}::its::ITS`).objectId;
    });

    it('Should not rotate to empty signers', async () => {
        console.log(its);
    });
});
