require('dotenv').config();
const { TxBuilder } =  require('../dist/tx-builder');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { publishPackage } = require('./utils');

describe('test', () => {
    let client, keypair;
    before(async() => {
        client = new SuiClient({ url: getFullnodeUrl('localnet') });
        const privKey = Buffer.from(process.env.SUI_PRIVATE_KEY, 'hex');

        keypair = Ed25519Keypair.fromSecretKey(privKey);
        await requestSuiFromFaucetV0({
            host: getFaucetHost('localnet'),
            recipient: keypair.toSuiAddress(),
        });
        let result = await publishPackage(client, keypair, 'abi');
        const abiPackageId = result.packageId;
        const abiCap = result.publishTxn.objectChanges.find((change) => change.objectType === `0x2::package::UpgradeCap`).objectId;

        result = await publishPackage(client, keypair, 'axelar_gateway');
        const axelarPackageId = result.packageId;
        const axelarCap = result.publishTxn.objectChanges.find((change) => change.objectType === `0x2::package::UpgradeCap`).objectId;

        result = await publishPackage(client, keypair, 'gas_service');
        const gasServicePackageId = result.packageId;
        const gasServiceCap = result.publishTxn.objectChanges.find((change) => change.objectType === `0x2::package::UpgradeCap`).objectId;

        result = await publishPackage(client, keypair, 'governance');
        const governancePackageId = result.packageId;
        const governanceCap = result.publishTxn.objectChanges.find((change) => change.objectType === `0x2::package::UpgradeCap`).objectId;

        result = await publishPackage(client, keypair, 'its');
        const itsPackageId = result.packageId;
        const itsCap = result.publishTxn.objectChanges.find((change) => change.objectType === `0x2::package::UpgradeCap`).objectId;

        result = await publishPackage(client, keypair, 'squid');
        const squidPackageId = result.packageId;
        const squidCap = result.publishTxn.objectChanges.find((change) => change.objectType === `0x2::package::UpgradeCap`).objectId;
        
        result = await publishPackage(client, keypair, 'test');
        const testPackageId = result.packageId;
        const testCap = result.publishTxn.objectChanges.find((change) => change.objectType === `0x2::package::UpgradeCap`).objectId;
    });
    it('test', async () => {

    });
});