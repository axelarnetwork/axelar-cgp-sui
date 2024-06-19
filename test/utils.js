
require('dotenv').config();
const { TxBuilder } =  require('../dist/tx-builder');
const { updateMoveToml } =  require('../dist/utils');


async function publishPackage(client, keypair, packageName) {
        const builder = new TxBuilder(client);
        await builder.publishPackageAndTransferCap(packageName, keypair.toSuiAddress());
        const publishTxn = await builder.signAndExecute(keypair);

        const packageId = (publishTxn.objectChanges?.find((a) => a.type === 'published') ?? []).packageId;

        updateMoveToml(packageName, packageId);
        return { packageId, publishTxn };
}

module.exports = {
    publishPackage,
}