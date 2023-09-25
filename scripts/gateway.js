require('dotenv').config();
const {BCS, fromHEX, getSuiMoveConfig} = require("@mysten/bcs");
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const secp256k1 = require('secp256k1');
const {
    utils: { keccak256 },
} = require('ethers');
const axelarInfo = require('../info/axelar.json');

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
        payload_hash: "vector<u8>",
    });

    return bcs;
}

function getOperators() {
    if(!axelarInfo.activeOperators) {
        return {
            privKeys: [], 
            weights: [], 
            threashold: 0,
        };
    }
    return axelarInfo.activeOperators;
}

function getRandomOperators(n = 5) {
    const privKeys = [];
    for(let i=0; i<n; i++) {
        privKeys.push(
            keccak256(Math.floor(Math.random()*10000000)).slice(2),
        );
    }

    const pubKeys = privKeys.map(privKey => secp256k1.publicKeyCreate(Buffer.from(privKey, 'hex')));
    const weights = privKeys.map(privKey => 3);
    const threashold = privKeys.length * 2;
    return {
        privKeys,
        pubKeys,
        weights,
        threashold,
    }
}

function getInputForMessage(message) {
    const operators = getOperators();

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
            threshold: operators.threashold,
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

function approveContractCallInput(sourceChain, sourceAddress, destinationAddress, payloadHash, commandId = keccak256((new Date()).getTime())) {
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
        
        return getInputForMessage(message);
}

function TransferOperatorshipInput(newOperators, newWeights, newThreshold, commandId = keccak256((new Date()).getTime())) {
    const privKey = Buffer.from(
        process.env.SUI_PRIVATE_KEY,
        "hex"
    );

    // get the public key in a compressed format
    const pubKey = secp256k1.publicKeyCreate(privKey);

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

        return getInputForMessage(message);
}

async function approveContractCall(client, keypair, sourceChain, sourceAddress, destinationAddress, payloadHash) {
    const commandId = keccak256((new Date()).getTime());
    const input = approveContractCallInput(sourceChain, sourceAddress, destinationAddress, payloadHash, commandId);
    const packageId = axelarInfo.packageId;
    const validators = axelarInfo['validators::AxelarValidators'];

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
    });
    return commandId;
}

async function transferOperatorship(client, keypair, newOperators, newWeights, newThreshold ) {
    const input = TransferOperatorshipInput( newOperators, newWeights, newThreshold);
    const packageId = axelarInfo.packageId;
    const validators = axelarInfo['validators::AxelarValidators'];

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
    });
    console.log(approveTxn.effects.status);
}

async function executeContractCall(client, keypair, sourceChain, sourceAddress, destinationAddress, payload, commandId) {
    const packageId = axelarInfo.packageId;
    const validators = axelarInfo['validators::AxelarValidators'];
    const test = axelarInfo['test_receive_call::Singleton'];
    console.log(destinationAddress);
    const channel = await client.getObject({id: destinationAddress.slice(2), options: {showFields: true}});
    console.log(channel);
    return;
    
    const payload_hash = arrayify(keccak256(payload));

	const tx = new TransactionBlock(); 
    const approvedCall = tx.moveCall({
        target: `${packageId}::gateway::take_approved_call`,
        arguments: [
            tx.object(validators.objectId), 
            tx.pure(commandId),
            tx.pure(sourceChain),
            tx.pure(sourceAddress),
            tx.pure(destinationAddress),
            tx.pure(String.fromCharCode(...arrayify(payload))),
        ],
        typeArguments: [],
    });
    tx.moveCall({
        target: `${packageId}::test_receive_call::execute`,
        arguments: [
            tx.object(test.objectId),
            approvedCall,
        ],
        typeArguments: []
    });

    const executeTxn = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
}

module.exports = {
    approveContractCall,
    transferOperatorship,
    getRandomOperators,
    executeContractCall,
}
