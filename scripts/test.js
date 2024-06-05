require('dotenv').config();
const { setConfig, getFullObject, requestSuiFromFaucet, updateMoveToml } = require('./utils');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { SuiClient } = require('@mysten/sui.js/client');
const { execSync } = require('child_process');
const { parseEnv } = require('./utils');
const tmp = require('tmp');
const fs = require('fs');
const path = require('path');
const { publishPackage } = require("./publish-package");
const { bcs } = require('@mysten/bcs');
const {
    utils: { arrayify, hexlify },
} = require('ethers');


(async () => {
    const env = parseEnv('localnet');
    const privKey = Buffer.from(process.env.SUI_PRIVATE_KEY, 'hex');
    const keypair = Ed25519Keypair.fromSecretKey(privKey);
    // create a new SuiClient object pointing to the network you want to use
    const client = new SuiClient({ url: env.url });
    const {packageId, publishTxn} = await publishPackage('test', client, keypair);
    const singleton = publishTxn.objectChanges.find((change) => change.objectType == `${packageId}::test::Singleton`);
    
    const func = await client.getNormalizedMoveFunction({package: packageId, module: 'test', function: "test"});

    const types = func.parameters.map(parameter => parameter.toLowerCase());
    const args = [
        "0x9027dcb35b21318572bda38641b394eb33896aa81878a4f0e7066b119a9ea000",
        13453453423423,
        13453453423423,
    ];
    bcs.address = () => bcs.fixedArray(32, bcs.u8()).transform({
        input: (id) => arrayify(id),
        output: (id) => hexlify(id),
    });

    bcs.vectorU8 = () => bcs.vector(bcs.u8()).transform({
        input: (input) => {
            if(typeof(input) === 'string') input = arrayify(input);
            return input;
        }
    })

    const serialize = (type, arg) => {
        const serializer = (type) => {
            if (typeof(type) === 'string') {
                return bcs[type]();
            } else if (type.Vector) {
                if(type.Vector === 'U8') {
                    return bcs.vectorU8();
                }
                return bcs.vector(serializer(type.Vector));
            } else {
                return null;
            }
        }
        return serializer(type).serialize(arg).toBytes();
    }

    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${packageId}::test::test`,
        arguments: types.map((type, index) => {
            return tx.pure(serialize(type, args[index]));
        }),
    });

    await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair
    })
})();