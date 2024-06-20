const { keccak256, defaultAbiCoder } = require('ethers/lib/utils');
const { TxBuilder } = require('../dist/tx-builder');
const { updateMoveToml } = require('../dist/utils');

async function publishPackage(client, keypair, packageName) {
    const builder = new TxBuilder(client);
    await builder.publishPackageAndTransferCap(packageName, keypair.toSuiAddress());
    const publishTxn = await builder.signAndExecute(keypair);

    const packageId = (publishTxn.objectChanges?.find((a) => a.type === 'published') ?? []).packageId;

    updateMoveToml(packageName, packageId);
    return { packageId, publishTxn };
}

function getRandomBytes32() {
    return keccak256(defaultAbiCoder.encode(['string'], [Math.random().toString()]));
}

module.exports = {
    publishPackage,
    getRandomBytes32,
};
