require('dotenv').config();

const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const {BcsReader, BCS, fromHEX, getSuiMoveConfig, bcs: bcsEncoder} = require("@mysten/bcs");
const {
    utils: { keccak256, arrayify, hexlify },
} = require('ethers');
const { approveContractCall } = require('./gateway');
const { toPure } = require('./utils');

async function receiveCall(client, keypair, axelarInfo, sourceChain, sourceAddress, destinationAddress, payload) {
    const axelarPackageId = axelarInfo.packageId;
    const gateway = axelarInfo['gateway::Gateway'];
    const discovery = axelarInfo['discovery::RelayerDiscovery'];
    const payloadHash = keccak256(payload);

    await approveContractCall(client, keypair, axelarInfo, sourceChain, sourceAddress, destinationAddress, payloadHash);
 
    const eventData = (await client.queryEvents({query: {
        MoveEventType: `${axelarPackageId}::gateway::ContractCallApproved`,
    }}));
    let event = eventData.data[0].parsedJson;

    let tx = new TransactionBlock();

    tx.moveCall({
        target: `${axelarPackageId}::discovery::get_transaction`,
        arguments: [tx.object(discovery.objectId), tx.pure(event.target_id)],
    });
    let resp = await client.devInspectTransactionBlock({
        sender: keypair.getPublicKey().toSuiAddress(),
        transactionBlock: tx,
    });
    
    tx = new TransactionBlock();
    tx.moveCall(decodeTransaction(tx, resp.results[0].returnValues[0][0], payload));
    resp = await client.devInspectTransactionBlock({
        sender: keypair.getPublicKey().toSuiAddress(),
        transactionBlock: tx,
        
    });
    
    tx = new TransactionBlock();
    
    const approvedCall = tx.moveCall({
        target: `${axelarPackageId}::gateway::take_approved_call`,
        arguments: [
            tx.object(gateway.objectId), 
            tx.pure(event.cmd_id),
            tx.pure(event.source_chain),
            tx.pure(event.source_address),
            tx.pure(event.target_id),
            tx.pure(String.fromCharCode(...arrayify(payload))),
        ],
        typeArguments: [],
    });
    const calls = getTransactionBlock(tx, resp.results[0].returnValues[0][0]);
    const returns = [];
    for(const call of calls) {
        returns.push(tx.moveCall(buildTransaction(tx, call, null, approvedCall, returns)));
    }
    await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
}

function getTransactionBcs() {
    const bcs = new BCS(getSuiMoveConfig());

    // input argument for the tx
    bcs.registerStructType("Function", {
        packageId: "address",
        module_name: "string",
        name: "string",
    });
    bcs.registerStructType("Transaction", {
        function: "Function",
        arguments: "vector<vector<u8>>",
        type_arguments: "vector<string>",
    });
    return bcs;
}
function buildTransaction(tx, txInfo, payload, callContractObj, previousReturns) {
    const decodeArgs = (args, tx) => args.map(arg => {
        if(arg[0] === 0) {
            return tx.object(hexlify(arg.slice(1)));
        } else if (arg[0] === 1) {
            return tx.pure(arg.slice(1));
        } else if (arg[0] === 2) {
            return callContractObj
        } else if (arg[0] === 3) {
            return tx.pure(bcs.ser('vector<u8>', arrayify(payload)).toBytes());
        } else if (arg[0] === 4) {
            return previousReturns[arg[1]][arg[2]];
        } else {
            throw new Error(`Invalid argument prefix: ${arg[0]}`);
        }
    });
    const decodeDescription = (description) => `${description.packageId}::${description.module_name}::${description.name}`;
    return {
        target: decodeDescription(txInfo.function),
        arguments: decodeArgs(txInfo.arguments, tx),
        typeArguments: txInfo.type_arguments,
    };
}
function decodeTransaction(tx, txData, payload) {
    const bcs = getTransactionBcs();
    let txInfo = bcs.de('Transaction', new Uint8Array(txData));

    return buildTransaction(tx, txInfo, payload);
}
function getTransactionBlock(tx, txData, callContractObj, previousReturns) {
    const bcs = getTransactionBcs();
    return bcs.de('vector<Transaction>', new Uint8Array(txData));
}

module.exports = {
    receiveCall,
}
if (require.main === module) {
    (async () => {
        const env = process.argv[2] || 'localnet';
        const axelarInfo = require('../info/axelar.json')[env];
        const testInfo = require('../info/test.json')[env];
        const privKey = Buffer.from(
            process.env.SUI_PRIVATE_KEY,
            "hex"
        );

        const discovery = axelarInfo['discovery::RelayerDiscovery'];

        // get the public key in a compressed format
        const keypair = Ed25519Keypair.fromSecretKey(privKey);
        // create a new SuiClient object pointing to the network you want to use
        const client = new SuiClient({ url: getFullnodeUrl(env) });
        
        const testPackageId = testInfo.packageId;
        const test = testInfo['test::Singleton'];
        
        const payload = '0x1234';

        let tx = new TransactionBlock();
        tx.moveCall({
            target: `${testPackageId}::test::register_transaction`,
            arguments: [tx.object(discovery.objectId), tx.object(test.objectId)],
        });
        await client.signAndExecuteTransactionBlock({       
            transactionBlock: tx,
            signer: keypair,
            options: {
                showEffects: true,
                showObjectChanges: true,
            },
        });

        await receiveCall(client, keypair, axelarInfo, 'Ethereum', '0x0', test.channel, payload);
        
        const event = (await client.queryEvents({query: {
            MoveEventType: `${testPackageId}::test::Executed`,
        }})).data[0].parsedJson;
        
        if ( hexlify(event.data) != payload ) throw new Error(`Emmited payload missmatch: ${hexlify(event.data)} != ${payload}`);
        
    })();
}