const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { setConfig, getConfig, getFullObject } = require('./utils');

async function initializeGovernance(upgradeCap, client, keypair, env) {
    const governanceConfig = getConfig('governance', env.alias);
    const packageId = governanceConfig.packageId;

    let tx = new TransactionBlock();
    tx.moveCall({
        target: `${packageId}::governance::new`,
        arguments: [
            tx.pure.string('Axelar'),
            tx.pure.string('the governance source addresss'),
            tx.pure.u256(0),
            tx.object(upgradeCap.objectId),
        ],
        typeArguments: [],
    });
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

    const governance = publishTxn.objectChanges.find((obj) => obj.objectType == `${packageId}::governance::Governance`);

    governanceConfig['governance::Governance'] = await getFullObject(governance, client);
    setConfig('governance', env.alias, governanceConfig);

    return governance;
}

async function takeUpgradeCaps(upgradeCaps, client, keypair, env) {
    const governanceConfig = getConfig('governance', env.alias);
    const packageId = governanceConfig.packageId;
    tx = new TransactionBlock();
    for (const upgradeCap of upgradeCaps) {
        tx.moveCall({
            target: `${packageId}::governance::take_upgrade_cap`,
            arguments: [tx.object(governanceConfig['governance::Governance'].objectId), tx.object(upgradeCap.objectId)],
            typeArguments: [],
        });
    }

    return await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showContent: true,
        },
        requestType: 'WaitForLocalExecution',
    });
}

module.exports = {
    initializeGovernance,
    takeUpgradeCaps,
};
