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

async function expectRevert(builder, keypair, error = {}) {
    try {
        await builder.signAndExecute(keypair);
        throw new Error(`Expected revert with ${error} but exeuted successfully instead`);
    } catch (e) {
        const errorMessage = e.cause.effects.status.error;
        let regexp = /address: (.*?),/;
        const packageId = `0x${regexp.exec(errorMessage)[1]}`;

        regexp = /Identifier\("(.*?)"\)/;
        const module = regexp.exec(errorMessage)[1];

        regexp = /Some\("(.*?)"\)/;
        const functionName = regexp.exec(errorMessage)[1];

        regexp = /Some\(".*?"\) \}, (.*?)\)/;
        const errorCode = parseInt(regexp.exec(errorMessage)[1]);

        if (error.packageId && error.packageId !== packageId) {
            throw new Error(`Expected ${errorMessage} to match ${error}} but it didn't, ${error.packageId} !== ${packageId}`);
        }

        if (error.module && error.module !== module) {
            throw new Error(`Expected ${errorMessage} to match ${error}} but it didn't, ${error.module} !== ${module}`);
        }

        if (error.function && error.function !== functionName) {
            throw new Error(`Expected ${errorMessage} to match ${error}} but it didn't, ${error.function} !== ${functionName}`);
        }

        if (error.code && error.code !== errorCode) {
            throw new Error(`Expected ${errorMessage} to match ${error}} but it didn't, ${error.code} !== ${errorCode}`);
        }
    }
}

module.exports = {
    publishPackage,
    getRandomBytes32,
    expectRevert,
};
