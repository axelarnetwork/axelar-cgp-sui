const { keccak256, defaultAbiCoder, arrayify } = require('ethers/lib/utils');
const { TxBuilder } = require('../dist/tx-builder');
const { updateMoveToml, copyMovePackage } = require('../dist/utils');
const chai = require('chai');
const { expect } = chai;
const {
    bcsStructs: {
        gateway: { WeightedSigners, MessageToSign, Proof, Message },
    },
} = require('../dist/bcs');
const { bcs } = require('@mysten/sui/bcs');
const secp256k1 = require('secp256k1');

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

async function approveContractCall(client, keypair, gatewayInfo, contractCallInfo) {
    const {packageId, gateway, signers, signerKeys, domainSeparator} = gatewayInfo;
    const  messageData = bcs.vector(Message).serialize([contractCallInfo]).toBytes();

    const hashed = hashMessage(messageData, COMMAND_TYPE_APPROVE_MESSAGES);

    const message = MessageToSign.serialize({
        domain_separator: domainSeparator,
        signers_hash: keccak256(WeightedSigners.serialize(signers).toBytes()),
        data_hash: hashed,
    }).toBytes();

    const signatures = signMessage(signerKeys, message);
    const encodedProof = Proof.serialize({
        signers: signers,
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
        arguments: [
            contractCallInfo.payload_hash,
        ],
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

async function getCalls(client, calls) {
    const builder = new TxBuilder(client);

    if(!Array.isArray(calls)) {
        calls = [ calls ];
    }
    
    for( const call of calls) {
        await builder.moveCall({
            target: `${packageId}::discovery::get_transaction`,
            arguments: [discovery, contractCallInfo.destination_id],
        });
    }

    const resp = await builder.devInspect(keypair.toSuiAddress());

    console.log(resp.results.returnValues[0]);
}

async function approveAndExecuteContractCall(client, keypair, gatewayInfo, contractCallInfo) {
    const {packageId, gateway, signers, signerKeys, domainSeparator, discovery} = gatewayInfo;

    await approveContractCall(client, keypair, gatewayInfo, contractCallInfo);

    
}

module.exports = {
    publishPackage,
    getRandomBytes32,
    expectRevert,
    expectEvent,
    hashMessage,
    signMessage,
    approveContractCall,
    approveAndExecuteContractCall,
};
