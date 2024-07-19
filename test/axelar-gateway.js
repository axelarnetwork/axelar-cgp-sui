const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { Secp256k1Keypair } = require('@mysten/sui.js/keypairs/secp256k1');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { publishPackage, getRandomBytes32, expectRevert, expectEvent } = require('./utils');
const { TxBuilder } = require('../dist/tx-builder');
const {
    bcsStructs: {
        gateway: { WeightedSigners, MessageToSign, Proof },
    },
} = require('../dist/bcs');
const { arrayify, hexlify, keccak256 } = require('ethers/lib/utils');
const secp256k1 = require('secp256k1');

const COMMAND_TYPE_ROTATE_SIGNERS = 1;

describe('Axelar Gateway', () => {
    let client;
    const operator = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const deployer = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const keypair = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const domainSeparator = getRandomBytes32();
    const network = process.env.NETWORK || 'localnet';
    let operatorKeys;
    let signers;
    let nonce = 0;
    let packageId;
    let gateway;

    function calculateNextSigners() {
        operatorKeys = [getRandomBytes32(), getRandomBytes32(), getRandomBytes32()];
        const pubKeys = operatorKeys.map((key) => Secp256k1Keypair.fromSecretKey(arrayify(key)).getPublicKey().toRawBytes());
        const keys = operatorKeys.map((key, index) => {
            return { privKey: key, pubKey: pubKeys[index] };
        });
        keys.sort((key1, key2) => {
            for (let i = 0; i < 33; i++) {
                if (key1.pubKey[i] < key2.pubKey[i]) return -1;
                if (key1.pubKey[i] > key2.pubKey[i]) return 1;
            }

            return 0;
        });
        operatorKeys = keys.map((key) => key.privKey);
        signers = {
            signers: keys.map((key) => {
                return { pub_key: key.pubKey, weight: 1 };
            }),
            threshold: 2,
            nonce: hexlify([++nonce]),
        };
    }

    function hashMessage(data) {
        const toHash = new Uint8Array(data.length + 1);
        toHash[0] = COMMAND_TYPE_ROTATE_SIGNERS;
        toHash.set(data, 1);

        return keccak256(toHash);
    }

    function sign(privKeys, messageToSign) {
        const signatures = [];

        for (const privKey of privKeys) {
            const { signature, recid } = secp256k1.ecdsaSign(arrayify(keccak256(messageToSign)), arrayify(privKey));
            signatures.push(new Uint8Array([...signature, recid]));
        }

        return signatures;
    }

    async function sleep(ms = 1000) {
        await new Promise((resolve) => setTimeout(resolve, ms));
    }

    const minimumRotationDelay = 1000;
    const previousSignersRetention = 15;

    before(async () => {
        client = new SuiClient({ url: getFullnodeUrl(network) });

        await Promise.all(
            [operator, deployer, keypair].map((keypair) =>
                requestSuiFromFaucetV0({
                    host: getFaucetHost(network),
                    recipient: keypair.toSuiAddress(),
                }),
            ),
        );

        let result = await publishPackage(client, deployer, 'axelar_gateway');
        packageId = result.packageId;
        const creatorCap = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${packageId}::gateway::CreatorCap`,
        ).objectId;

        calculateNextSigners();

        const encodedSigners = WeightedSigners.serialize(signers).toBytes();
        const builder = new TxBuilder(client);

        const separator = await builder.moveCall({
            target: `${packageId}::bytes32::new`,
            arguments: [domainSeparator],
        });

        await builder.moveCall({
            target: `${packageId}::gateway::setup`,
            arguments: [
                creatorCap,
                operator.toSuiAddress(),
                separator,
                minimumRotationDelay,
                previousSignersRetention,
                encodedSigners,
                '0x6',
            ],
        });

        result = await builder.signAndExecute(deployer);

        gateway = result.objectChanges.find((change) => change.objectType === `${packageId}::gateway::Gateway`).objectId;
    });

    describe('Signer Rotation', () => {
        it('Should rotate signers', async () => {
            await sleep(2000);
            const proofSigners = signers;
            const proofKeys = operatorKeys;
            calculateNextSigners();

            const encodedSigners = WeightedSigners.serialize(signers).toBytes();

            const hashed = hashMessage(encodedSigners);

            const message = MessageToSign.serialize({
                domain_separator: domainSeparator,
                signers_hash: keccak256(WeightedSigners.serialize(proofSigners).toBytes()),
                data_hash: hashed,
            }).toBytes();

            const signatures = sign(proofKeys, message);
            const encodedProof = Proof.serialize({
                signers: proofSigners,
                signatures,
            }).toBytes();

            const builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${packageId}::gateway::rotate_signers`,
                arguments: [gateway, '0x6', encodedSigners, encodedProof],
            });

            await builder.signAndExecute(keypair);
        });

        it('Should not rotate to empty signers', async () => {
            await sleep(2000);
            const proofSigners = signers;
            const proofKeys = operatorKeys;

            const encodedSigners = WeightedSigners.serialize({
                signers: [],
                threshold: 2,
                nonce: hexlify([nonce + 1]),
            }).toBytes();

            const hashed = hashMessage(encodedSigners);

            const message = MessageToSign.serialize({
                domain_separator: domainSeparator,
                signers_hash: keccak256(WeightedSigners.serialize(proofSigners).toBytes()),
                data_hash: hashed,
            }).toBytes();

            const signatures = sign(proofKeys, message);
            const encodedProof = Proof.serialize({
                signers: proofSigners,
                signatures,
            }).toBytes();

            const builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${packageId}::gateway::rotate_signers`,
                arguments: [gateway, '0x6', encodedSigners, encodedProof],
            });

            await expectRevert(builder, keypair, {
                packageId,
                module: 'weighted_signers',
                function: 'peel',
                code: 0,
            });
        });
    });

    describe('Contract Call', () => {
        let channel;
        before(async () => {
            const builder = new TxBuilder(client);

            channel = await builder.moveCall({
                target: `${packageId}::channel::new`,
                arguments: [],
                typeArguments: [],
            });

            builder.tx.transferObjects([channel], keypair.toSuiAddress());

            const response = await builder.signAndExecute(keypair);

            channel = response.objectChanges.find((change) => change.objectType === `${packageId}::channel::Channel`).objectId;
        });

        it('Make Contract Call', async () => {
            const destinationChain = 'Destination Chain';
            const destinationAddress = 'Destination Address';
            const payload = '0x1234';
            const builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${packageId}::gateway::call_contract`,
                arguments: [channel, destinationChain, destinationAddress, payload],
                typeArguments: [],
            });

            await expectEvent(builder, keypair, {
                type: `${packageId}::gateway::ContractCall`,
                arguments: {
                    destination_address: destinationAddress,
                    destination_chain: destinationChain,
                    payload: arrayify(payload),
                    payload_hash: keccak256(payload),
                    source_id: channel,
                },
            });
        });
    });
});
