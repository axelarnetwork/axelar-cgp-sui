const { keccak256, defaultAbiCoder, arrayify, hexlify } = require('ethers/lib/utils');
const { TxBuilder } = require('../dist/tx-builder');
const { updateMoveToml, copyMovePackage } = require('../dist/utils');
const { Ed25519Keypair } = require('@mysten/sui/keypairs/ed25519');
const chai = require('chai');
const { expect } = chai;
const {
    bcsStructs: {
        gateway: { WeightedSigners, MessageToSign, Proof, Message, Transaction },
    },
} = require('../dist/bcs');
const { bcs } = require('@mysten/sui/bcs');
const secp256k1 = require('secp256k1');

const COMMAND_TYPE_APPROVE_MESSAGES = 0;
const clock = '0x6';
async function publishPackage(client, keypair, packageName) {
    const compileDir = `${__dirname}/../move_compile`;
    copyMovePackage(packageName, null, compileDir);
    const builder = new TxBuilder(client);
    await builder.publishPackageAndTransferCap(packageName, keypair.toSuiAddress(), compileDir);
    const publishTxn = await builder.signAndExecute(keypair);

    const packageId = (publishTxn.objectChanges?.find((a) => a.type === 'published') ?? []).packageId;

    updateMoveToml(packageName, packageId, compileDir);
    return { packageId, publishTxn };
}

function generateEd25519Keypairs(length) {
    return Array.from({ length }, () => Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32())));
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

async function expectEvent(builder, keypair, eventData = {}) {
    const response = await builder.signAndExecute(keypair, { showEvents: true });

    const event = response.events.find((event) => event.type === eventData.type);

    function compare(a, b) {
        if (Array.isArray(a)) {
            expect(a.length).to.equal(b.length);

            for (let i = 0; i < a.length; i++) {
                compare(a[i], b[i]);
            }

            return;
        }

        expect(a).to.equal(b);
    }

    for (const key of Object.keys(eventData.arguments)) {
        compare(event.parsedJson[key], eventData.arguments[key]);
    }
}

function hashMessage(data, commandType) {
    const toHash = new Uint8Array(data.length + 1);
    toHash[0] = commandType;
    toHash.set(data, 1);

    return keccak256(toHash);
}

function signMessage(privKeys, messageToSign) {
    const signatures = [];

    for (const privKey of privKeys) {
        const { signature, recid } = secp256k1.ecdsaSign(arrayify(keccak256(messageToSign)), arrayify(privKey));
        signatures.push(new Uint8Array([...signature, recid]));
    }

    return signatures;
}

async function approveMessage(client, keypair, gatewayInfo, contractCallInfo) {
    const { packageId, gateway, signers, signerKeys, domainSeparator } = gatewayInfo;
    const messageData = bcs.vector(Message).serialize([contractCallInfo]).toBytes();

    const hashed = hashMessage(messageData, COMMAND_TYPE_APPROVE_MESSAGES);

    const message = MessageToSign.serialize({
        domain_separator: domainSeparator,
        signers_hash: keccak256(WeightedSigners.serialize(signers).toBytes()),
        data_hash: hashed,
    }).toBytes();

    const signatures = signMessage(signerKeys, message);
    const encodedProof = Proof.serialize({
        signers,
        signatures,
    }).toBytes();

    let builder = new TxBuilder(client);

    await builder.moveCall({
        target: `${packageId}::gateway::approve_messages`,
        arguments: [gateway, messageData, encodedProof],
    });

    await builder.signAndExecute(keypair);

    builder = new TxBuilder(client);

    const payloadHash = await builder.moveCall({
        target: `${packageId}::bytes32::new`,
        arguments: [contractCallInfo.payload_hash],
    });

    await builder.moveCall({
        target: `${packageId}::gateway::is_message_approved`,
        arguments: [
            gateway,
            contractCallInfo.source_chain,
            contractCallInfo.message_id,
            contractCallInfo.source_address,
            contractCallInfo.destination_id,
            payloadHash,
        ],
    });
}

async function approveAndExecuteMessage(client, keypair, gatewayInfo, messageInfo, executeOptions) {
    const axelarPackageId = gatewayInfo.packageId;
    const gateway = gatewayInfo.gateway;
    const discovery = gatewayInfo.discovery;

    await approveMessage(client, keypair, gatewayInfo, messageInfo);

    const discoveryArg = [0];
    discoveryArg.push(...arrayify(discovery));
    const targetIdArg = [1];
    targetIdArg.push(...arrayify(messageInfo.destination_id));
    let moveCalls = [
        {
            function: {
                package_id: axelarPackageId,
                module_name: 'discovery',
                name: 'get_transaction',
            },
            arguments: [discoveryArg, targetIdArg],
            type_arguments: [],
        },
    ];
    let isFinal = false;

    while (!isFinal) {
        const builder = new TxBuilder(client);
        makeCalls(builder.tx, moveCalls, messageInfo.payload);
        const resp = await builder.devInspect(keypair.toSuiAddress());

        const txData = resp.results[0].returnValues[0][0];
        const nextTx = Transaction.parse(new Uint8Array(txData));
        isFinal = nextTx.is_final;
        moveCalls = nextTx.move_calls;
    }

    const builder = new TxBuilder(client);
    const ApprovedMessage = await builder.moveCall({
        target: `${axelarPackageId}::gateway::take_approved_message`,
        arguments: [
            gateway,
            messageInfo.source_chain,
            messageInfo.message_id,
            messageInfo.source_address,
            messageInfo.destination_id,
            messageInfo.payload,
        ],
    });
    makeCalls(builder.tx, moveCalls, messageInfo.payload, ApprovedMessage);
    return await builder.signAndExecute(keypair, executeOptions);
}

function makeCalls(tx, moveCalls, payload, ApprovedMessage) {
    const returns = [];

    for (const call of moveCalls) {
        let result = tx.moveCall(buildMoveCall(tx, call, payload, ApprovedMessage, returns));
        if (!Array.isArray(result)) result = [result];
        returns.push(result);
    }
}

function buildMoveCall(tx, moveCallInfo, payload, callContractObj, previousReturns) {
    const decodeArgs = (args, tx) =>
        args.map((arg) => {
            if (arg[0] === 0) {
                return tx.object(hexlify(arg.slice(1)));
            } else if (arg[0] === 1) {
                return tx.pure(new Uint8Array(arg.slice(1)));
            } else if (arg[0] === 2) {
                return callContractObj;
            } else if (arg[0] === 3) {
                return tx.pure(bcs.vector(bcs.U8).serialize(arrayify(payload)));
            } else if (arg[0] === 4) {
                return previousReturns[arg[1]][arg[2]];
            }

            throw new Error(`Invalid argument prefix: ${arg[0]}`);
        });
    const decodeDescription = (description) => `${description.package_id}::${description.module_name}::${description.name}`;
    return {
        target: decodeDescription(moveCallInfo.function),
        arguments: decodeArgs(moveCallInfo.arguments, tx),
        typeArguments: moveCallInfo.type_arguments,
    };
}

function findObjectId(tx, objectType, type = 'created') {
    return tx.objectChanges.find((change) => change.type === type && change.objectType.includes(objectType))?.objectId;
}

module.exports = {
    clock,
    publishPackage,
    findObjectId,
    getRandomBytes32,
    expectRevert,
    expectEvent,
    hashMessage,
    signMessage,
    approveMessage,
    approveAndExecuteMessage,
    generateEd25519Keypairs,
};
