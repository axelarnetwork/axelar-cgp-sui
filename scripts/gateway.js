require('dotenv').config();
const {BCS, fromHEX, getSuiMoveConfig} = require("@mysten/bcs");
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const secp256k1 = require('secp256k1');
const { CosmWasmClient } = require('@cosmjs/cosmwasm-stargate');
const {
    utils: { keccak256 },
} = require('ethers');

function hashMessage(data) {
    // sorry for putting it here...
    const messagePrefix = new Uint8Array(
        Buffer.from("\x19Sui Signed Message:\n", "ascii")
    );
    let hashed = new Uint8Array(messagePrefix.length + data.length);
    hashed.set(messagePrefix);
    hashed.set(data, messagePrefix.length);

    return keccak256(hashed);
}

function getBcsForGateway() {
    const bcs = new BCS(getSuiMoveConfig());

    // input argument for the tx
    bcs.registerStructType("Input", {
        data: "vector<u8>",
        proof: "vector<u8>",
    });

    bcs.registerStructType("Proof", {
        // operators is a 33 byte / for now at least
        operators: "vector<vector<u8>>",
        weights: "vector<u128>",
        threshold: "u128",
        signatures: "vector<vector<u8>>",
    });

    // internals of the message
    bcs.registerStructType("AxelarMessage", {
        chain_id: "u64",
        command_ids: "vector<address>",
        commands: "vector<string>",
        params: "vector<vector<u8>>",
    });

    // internals of the message
    bcs.registerStructType("TransferOperatorshipMessage", {
        operators: "vector<vector<u8>>",
        weights: "vector<u128>",
        threshold: "u128",
    });
    bcs.registerStructType("GenericMessage", {
        source_chain: "string",
        source_address: "string",
        target_id: "address",
        payload_hash: "address",
    });

    return bcs;
}

function getOperators(axelarInfo) {
    if(!axelarInfo.activeOperators) {
        return {
            privKeys: [],
            weights: [],
            threshold: 0,
        };
    }
    return axelarInfo.activeOperators;
}

function getRandomOperators(n = 5) {
    let privKeys = [];
    for(let i=0; i<n; i++) {
        privKeys.push(
            keccak256(Math.floor(Math.random()*10000000)).slice(2),
        );
    }

    let pubKeys = privKeys.map(privKey => secp256k1.publicKeyCreate(Buffer.from(privKey, 'hex')));
    const indices = Array.from(pubKeys.keys())
    const pubKeyLength = 33;

    indices.sort( (a, b) => {
        for(let i = 0; i < pubKeyLength; i++) {
            const aByte = pubKeys[a][i];
            const bByte = pubKeys[b][i];
            if(aByte != bByte) return aByte - bByte;
        }
        return 0;
    } );
    pubKeys = indices.map(i => pubKeys[i]);
    privKeys = indices.map(i => privKeys[i]);
    const weights = privKeys.map(privKey => 3);
    const threshold = privKeys.length * 2;

    return {
        privKeys,
        pubKeys,
        weights,
        threshold,
    }
}

function getInputForMessage(info, message) {
    const operators = getOperators(info);
    // get the public key in a compressed format
    const pubKeys = operators.privKeys.map(privKey => secp256k1.publicKeyCreate(Buffer.from(privKey, 'hex')));

    const hashed = fromHEX(hashMessage(message));
    const signatures = operators.privKeys.map(privKey => {
        const {signature, recid} = secp256k1.ecdsaSign(hashed, Buffer.from(privKey, 'hex'));
        return new Uint8Array([...signature, recid]);
    })

    const bcs = getBcsForGateway();
    const proof =  bcs
        .ser("Proof", {
            operators: pubKeys,
            weights: operators.weights,
            threshold: operators.threshold,
            signatures,
        })
        .toBytes();

    const input = bcs
        .ser("Input", {
            data: message,
            proof: proof,
        })
        .toBytes();
    return input;
}

function approveContractCallInput(axelarInfo, sourceChain, sourceAddress, destinationAddress, payloadHash, commandId = keccak256((new Date()).getTime())) {
    const bcs = getBcsForGateway();

    const message = bcs
        .ser("AxelarMessage", {
            chain_id: 1,
            command_ids: [commandId],
            commands: ["approveContractCall"],
            params: [
                bcs
                    .ser("GenericMessage", {
                        source_chain: sourceChain,
                        source_address: sourceAddress,
                        payload_hash: payloadHash,
                        target_id: destinationAddress,
                    })
                    .toBytes(),
            ],
        })
        .toBytes();

        return getInputForMessage(axelarInfo, message);
}

function TransferOperatorshipInput(info, newOperators, newWeights, newThreshold, commandId = keccak256((new Date()).getTime())) {
    const bcs = getBcsForGateway();
    const message = bcs
        .ser("AxelarMessage", {
            chain_id: 1,
            command_ids: [commandId],
            commands: ["transferOperatorship"],
            params: [
                bcs
                    .ser("TransferOperatorshipMessage", {
                        operators: newOperators,
                        weights: newWeights,
                        threshold: newThreshold,
                    })
                    .toBytes(),
            ],
        })
        .toBytes();

        return getInputForMessage(info, message);
}

async function approveContractCall(client, keypair, axelarInfo, sourceChain, sourceAddress, destinationAddress, payloadHash) {
    const commandId = keccak256((new Date()).getTime());
    const input = approveContractCallInput(axelarInfo, sourceChain, sourceAddress, destinationAddress, payloadHash, commandId);
    const packageId = axelarInfo.packageId;
    const validators = axelarInfo['gateway::Gateway'];

	const tx = new TransactionBlock();
    tx.moveCall({
        target: `${packageId}::gateway::process_commands`,
        arguments: [tx.object(validators.objectId), tx.pure(String.fromCharCode(...input))],
        typeArguments: [],
    });
    const approveTxn = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForLocalExecution',
    });
    return commandId;
}

async function getAmplifierWorkers(rpc, proverAddr) {
    const client = await CosmWasmClient.connect(rpc);
    const workerSet = await client.queryContractSmart(proverAddr, 'get_worker_set');
    const signers = Object.values(workerSet.signers).sort((a, b) =>
        a.pub_key.ecdsa.toLowerCase().localeCompare(b.pub_key.ecdsa.toLowerCase())
    );

    const pubKeys = signers.map((signer) => Buffer.from(signer.pub_key.ecdsa, 'hex'));
    const weights = signers.map((signer) => Number(signer.weight));
    const threshold = Number(workerSet.threshold);

    return { pubKeys, weights, threshold };
};

async function transferOperatorship(info, client, keypair, newOperators, newWeights, newThreshold ) {
    const input = TransferOperatorshipInput(info, newOperators, newWeights, newThreshold);
    const packageId = info.packageId;
    const gateway = info['gateway::Gateway'];

	const tx = new TransactionBlock();
    tx.moveCall({
        target: `${packageId}::gateway::process_commands`,
        arguments: [tx.object(gateway.objectId), tx.pure(String.fromCharCode(...input))],
        typeArguments: [],
    });
    const approveTxn = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForLocalExecution',
    });
    console.log(approveTxn.effects.status);
}

module.exports = {
    approveContractCall,
    transferOperatorship,
    getRandomOperators,
    getAmplifierWorkers,
    getBcsForGateway,
    hashMessage,
}
