require('dotenv').config();

const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const {BcsReader, BCS, fromHEX, getSuiMoveConfig, bcs: bcsEncoder} = require("@mysten/bcs");
const {
    utils: { keccak256, arrayify, hexlify },
} = require('ethers');
const { approveContractCall } = require('./gateway');

async function receiveCall(client, keypair, axelarInfo, sourceChain, sourceAddress, destinationAddress, payload) {
    const axelarPackageId = axelarInfo.packageId;
    const gateway = axelarInfo['gateway::Gateway'];
    const discovery = axelarInfo['discovery::RelayerDiscovery'];
    const payloadHash = keccak256(payload);

    await approveContractCall(client, keypair, axelarInfo, sourceChain, sourceAddress, destinationAddress, payloadHash);
 
    const eventData = (await client.queryEvents({query: {
        MoveEventType: `${axelarPackageId}::gateway::ContractCallApproved`,
    }}));
    const event = eventData.data[0].parsedJson;

    const discoveryArg = [0];
    discoveryArg.push(...arrayify(discovery.objectId));
    const targetIdArg = [1];
    targetIdArg.push(...arrayify(event.target_id));
    let moveCalls = [
        {
            function: {
                package_id: axelarPackageId,
                module_name: 'discovery',
                name: 'get_transaction',
            },
            arguments: [discoveryArg, targetIdArg],
            type_arguments: [],
        }
    ];
    let is_final = false;
    while(!is_final) {
        const tx = new TransactionBlock();
        makeCalls(tx, moveCalls, payload);
        const resp = await client.devInspectTransactionBlock({
            sender: keypair.getPublicKey().toSuiAddress(),
            transactionBlock: tx,
        });
        const txData = resp.results[0].returnValues[0][0];
        const nextTx = getTransactionBcs().de('Transaction', new Uint8Array(txData));
        is_final = nextTx.is_final;
        moveCalls = nextTx.move_calls;
    }
    const tx = new TransactionBlock();

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
    makeCalls(tx, moveCalls, payload, approvedCall);
    return await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
}

function makeCalls(tx, moveCalls, payload, approvedCall) {
    const returns = [];
    for(const call of moveCalls) {
        let result = tx.moveCall(
            buildMoveCall(tx, call, payload, approvedCall, returns)
        );
        if(!Array.isArray(result)) result = [result];
        returns.push(result);
    }
}

function getTransactionBcs() {
    const bcs = new BCS(getSuiMoveConfig());

    // input argument for the tx
    bcs.registerStructType("Function", {
        package_id: "address",
        module_name: "string",
        name: "string",
    });
    bcs.registerStructType("MoveCall", {
        function: "Function",
        arguments: "vector<vector<u8>>",
        type_arguments: "vector<string>",
    });
    bcs.registerStructType("Transaction", {
        is_final: "bool",
        move_calls: "vector<MoveCall>",
    })
    return bcs;
}
function buildMoveCall(tx, moveCallInfo, payload, callContractObj, previousReturns) {
    const decodeArgs = (args, tx) => args.map(arg => {
        if(arg[0] === 0) {
            return tx.object(hexlify(arg.slice(1)));
        } else if (arg[0] === 1) {
            return tx.pure(new Uint8Array(arg.slice(1)));
        } else if (arg[0] === 2) {
            return callContractObj
        } else if (arg[0] === 3) {
            return tx.pure(bcsEncoder.vector(bcsEncoder.u8()).serialize(arrayify(payload)));
        } else if (arg[0] === 4) {
            return previousReturns[arg[1]][arg[2]];
        } else {
            throw new Error(`Invalid argument prefix: ${arg[0]}`);
        }
    });
    const decodeDescription = (description) => `${description.package_id}::${description.module_name}::${description.name}`;
    return {
        target: decodeDescription(moveCallInfo.function),
        arguments: decodeArgs(moveCallInfo.arguments, tx),
        typeArguments: moveCallInfo.type_arguments,
    };
}

module.exports = {
    receiveCall,
    getTransactionBcs,
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