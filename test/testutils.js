'use strict';

const { keccak256, defaultAbiCoder, randomBytes, arrayify, hexlify } = require('ethers/lib/utils');
const { TxBuilder } = require('../dist/tx-builder');
const { updateMoveToml, copyMovePackage } = require('../dist/utils');
const { Ed25519Keypair } = require('@mysten/sui/keypairs/ed25519');
const { Secp256k1Keypair } = require('@mysten/sui/keypairs/secp256k1');
const { fromB64 } = require('@mysten/bcs');
const chai = require('chai');
const { expect } = chai;
const {
    bcsStructs: {
        gateway: { WeightedSigners, MessageToSign, Proof, Message, Transaction },
        gmp: { Singleton },
        its: { TrustedAddresses },
    },
} = require('../dist/bcs');
const { newInterchainToken } = require('../dist/utils');
const { bcs } = require('@mysten/sui/bcs');
const secp256k1 = require('secp256k1');
const chalk = require('chalk');
const { diffJson } = require('diff');
const fs = require('fs');
const path = require('path');

const COMMAND_TYPE_APPROVE_MESSAGES = 0;

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

async function publishInterchainToken(client, keypair, options) {
    const templateFilePath = `${__dirname}/../move/interchain_token/sources/interchain_token.move`;

    const { filePath, content } = newInterchainToken(templateFilePath, options);

    fs.writeFileSync(filePath, content, 'utf8');

    const publishReceipt = await publishPackage(client, keypair, 'interchain_token');

    fs.rmSync(filePath);

    return publishReceipt;
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

/**
 *
 * @param {object} data Arbitrary data to be either written to a golden file
 *  or compared to an existing golden file, depending on whether `GOLDEN_TESTS` env var is set or not.
 * @param {string} name Name of the test. The golden file will be stored at `testdata/${name}.json`
 */
function goldenTest(data, name) {
    const goldenDir = path.resolve(__dirname, 'testdata');
    const goldenFilePath = path.join(goldenDir, `${name}.json`);
    const encodedData = JSON.stringify(data, null, 2) + '\n';

    if (process.env.GOLDEN_TESTS) {
        // Write the extracted info to the golden file
        fs.mkdirSync(path.dirname(goldenFilePath), { recursive: true });
        fs.writeFileSync(goldenFilePath, encodedData);
    } else {
        // Read the golden file and compare
        if (!fs.existsSync(goldenFilePath)) {
            throw new Error(`Golden file not found: ${goldenFilePath}`);
        }

        const expectedData = fs.readFileSync(goldenFilePath, 'utf8');

        if (encodedData !== expectedData) {
            const diff = diffJson(JSON.parse(expectedData), JSON.parse(encodedData));

            console.log(`Diff with ${goldenFilePath}:`);

            diff.forEach((part) => {
                const color = part.added ? 'green' : part.removed ? 'red' : '';

                if (color) {
                    process.stdout.write(chalk[color](part.value));
                }
            });

            console.log();

            expect(false).to.be.true(`Public interface for ${name} does not match golden file`);
        }
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

function calculateNextSigners(gatewayInfo, nonce) {
    const signerKeys = [getRandomBytes32(), getRandomBytes32(), getRandomBytes32()];
    const pubKeys = signerKeys.map((key) => Secp256k1Keypair.fromSecretKey(arrayify(key)).getPublicKey().toRawBytes());
    const keys = signerKeys.map((key, index) => {
        return { privKey: key, pubKey: pubKeys[index] };
    });
    keys.sort((key1, key2) => {
        for (let i = 0; i < 33; i++) {
            if (key1.pubKey[i] < key2.pubKey[i]) return -1;
            if (key1.pubKey[i] > key2.pubKey[i]) return 1;
        }

        return 0;
    });
    gatewayInfo.signerKeys = keys.map((key) => key.privKey);
    gatewayInfo.signers = {
        signers: keys.map((key) => {
            return { pub_key: key.pubKey, weight: 1 };
        }),
        threshold: 2,
        nonce: hexlify([++nonce]),
    };
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
    const discoveryPackageId = gatewayInfo.discoveryPackageId;
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
                package_id: discoveryPackageId,
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
        getSingletonChannelId,
    };
}

function findObjectId(tx, objectType, type = 'created') {
    return tx.objectChanges.find((change) => change.type === type && change.objectType.includes(objectType))?.objectId;
}

const getBcsBytesByObjectId = async (client, objectId) => {
    const response = await client.getObject({
        id: objectId,
        options: {
            showBcs: true,
        },
    });

    return fromB64(response.data.bcs.bcsBytes);
};

const getSingletonChannelId = async (client, singletonObjectId) => {
    const bcsBytes = await getBcsBytesByObjectId(client, singletonObjectId);
    const data = Singleton.parse(bcsBytes);
    console.log('getSingletonChannelId', data);
    return '0x' + data.channel.id;
};

async function setupTrustedAddresses(client, keypair, gatewayInfo, objectIds, deployments, trustedAddresses, trustedChains = ['Ethereum']) {
    const governanceInfo = {
        trustedSourceChain: 'Axelar',
        trustedSourceAddress: 'Governance Source Address',
        messageType: BigInt('0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68'),
    };

    // The payload is abi encoded, the trusted address data is bcs encoded.
    const trustedAddressesData = TrustedAddresses.serialize({
        trusted_chains: trustedChains,
        trusted_addresses: trustedAddresses,
    }).toBytes();

    const payload = defaultAbiCoder.encode(['uint256', 'bytes'], [governanceInfo.messageType, trustedAddressesData]);

    const trustedAddressMessage = {
        message_id: hexlify(randomBytes(32)),
        destination_id: objectIds.itsChannel,
        source_chain: governanceInfo.trustedSourceChain,
        source_address: governanceInfo.trustedSourceAddress,
        payload_hash: keccak256(payload),
    };

    console.log('destinationId', objectIds.itsChannel);

    await approveMessage(client, keypair, gatewayInfo, trustedAddressMessage);

    console.log('Approved trusted address message');

    // Set trusted addresses
    const trustedAddressTxBuilder = new TxBuilder(client);

    const approvedMessage = await trustedAddressTxBuilder.moveCall({
        target: `${deployments.axelar_gateway.packageId}::gateway::take_approved_message`,
        arguments: [
            objectIds.gateway,
            trustedAddressMessage.source_chain,
            trustedAddressMessage.message_id,
            trustedAddressMessage.source_address,
            trustedAddressMessage.destination_id,
            hexlify(payload),
        ],
    });

    console.log('Set trusted addresses', [objectIds.gateway, objectIds.governance, approvedMessage]);

    await trustedAddressTxBuilder.moveCall({
        target: `${deployments.its.packageId}::its::set_trusted_addresses`,
        arguments: [objectIds.its, objectIds.governance, approvedMessage],
    });

    const trustedAddressResult = await trustedAddressTxBuilder.signAndExecute(keypair);

    return trustedAddressResult;
}

module.exports = {
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
    calculateNextSigners,
    getBcsBytesByObjectId,
    getSingletonChannelId,
    setupTrustedAddresses,
    publishInterchainToken,
    goldenTest,
};
