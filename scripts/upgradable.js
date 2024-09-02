const { SuiClient, getFullnodeUrl } = require("@mysten/sui/client");
const { requestSuiFromFaucetV0, getFaucetHost } = require("@mysten/sui/faucet");
const { Ed25519Keypair } = require("@mysten/sui/keypairs/ed25519");
const { arrayify } = require("ethers/lib/utils");
const { getRandomBytes32, publishPackage } = require("../test/utils");
const { TxBuilder } = require("../dist/tx-builder");
const { copyMovePackage } = require("../dist/utils");
const { bcs } = require('@mysten/sui/bcs');

let upgradeCap, client, keypair, singleton;
let packageIds = {};

async function upgrade(from, to) {
    const policy = 0;

    copyMovePackage('upgradable', `move/upgradable/${to}`, 'move_compile');
    let builder = new TxBuilder(client);
    const { modules, dependencies, digest } = await builder.getContractBuild('upgradable', 'move_compile');
    const ticket = await builder.moveCall({
        target: `0x2::package::authorize_upgrade`,
        arguments: [
            upgradeCap,
            policy,
            digest
        ],
    });
    const receipt = builder.tx.upgrade({
        modules, 
        dependencies,
        package: packageIds[from],
        ticket
    });
    await builder.moveCall({
        target: `0x2::package::commit_upgrade`,
        arguments: [
            upgradeCap,
            receipt
        ],
    });
    const upgradeTx = await builder.signAndExecute(keypair);

    const packageId = upgradeTx.objectChanges.find((change) => change.type === 'published').packageId;

    packageIds[to] = packageId;
    
    builder = new TxBuilder(client);
    await builder.moveCall({
        target: `${packageId}::upgradable::upgrade`,
        arguments: [singleton],
    });
    await builder.signAndExecute(keypair);

    return {
        packageId, upgradeTx,
    }
}

async function set(version, value) {
    try {
        const builder = new TxBuilder(client);
        await builder.moveCall({
            target: `${packageIds[version]}::upgradable::set`,
            arguments: [
                singleton,
                value,
            ]
        });
        await builder.signAndExecute(keypair);
        console.log(`Succesfully set value on ${version} to ${value}`);
    } catch (e) {
        console.log(`Failed to set value on ${version} to ${value}`);
    }
}

async function get(version) {
    try {
        const builder = new TxBuilder(client);
        await builder.moveCall({
            target: `${packageIds[version]}::upgradable::get`,
            arguments: [
                singleton,
            ]
        });
        const resp = await builder.devInspect(keypair.toSuiAddress());
        const value = bcs.U64.parse(new Uint8Array(resp.results[0].returnValues[0][0]));
        console.log(`Succesfully got value on ${version} as ${value}`);
    } catch (e) {
        console.log(`Failed to get value on ${version}`);
    }
}

(async() => {
    const network = 'localnet';
    client = new SuiClient({ url: getFullnodeUrl(network) });
    keypair = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));

    await requestSuiFromFaucetV0({
        host: getFaucetHost(network),
        recipient: keypair.toSuiAddress(),
    });

    await publishPackage(client, keypair, 'version_control', 'move/upgradable');
    let response = await publishPackage(client, keypair, 'upgradable', 'move/upgradable/v1');
    packageIds.v1 = response.packageId;
    singleton = response.publishTxn.objectChanges.find((change) => change.objectType == `${response.packageId}::upgradable::Singleton`).objectId;
    upgradeCap = response.publishTxn.objectChanges.find((change) => change.objectType == `0x2::package::UpgradeCap`).objectId;
    
    await set('v1', 1);
    await get('v1');

    response = await upgrade('v1', 'v2');
        
    await set('v1', 2);
    await get('v1');
    await set('v2', 3);
    await get('v2');

    response = await upgrade('v2', 'v3');

    await set('v1', 4);
    await get('v1');
    await set('v2', 5);
    await get('v2');
    await set('v3', 6);
    await get('v3');
})();