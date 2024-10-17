const { SuiClient, getFullnodeUrl } = require('@mysten/sui/client');
const { Ed25519Keypair } = require('@mysten/sui/keypairs/ed25519');
const { Secp256k1Keypair } = require('@mysten/sui/keypairs/secp256k1');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui/faucet');
const { publishPackage, getRandomBytes32, expectRevert, expectEvent, approveMessage, hashMessage, signMessage } = require('./testutils');
const { approveAndExecute } = require('../dist/execute');
const { TxBuilder } = require('../dist/tx-builder');
const {
    bcsStructs: {
        gateway: { WeightedSigners, MessageToSign, Proof },
    },
} = require('../dist/bcs');
const { CLOCK_PACKAGE_ID } = require('../dist/types');
const { bcs } = require('@mysten/sui/bcs');
const { arrayify, hexlify, keccak256, defaultAbiCoder } = require('ethers/lib/utils');
const { expect } = require('chai');

const COMMAND_TYPE_ROTATE_SIGNERS = 1;

describe('Axelar Gateway', () => {
    let client;
    const operator = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const deployer = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const keypair = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const domainSeparator = getRandomBytes32();
    const network = process.env.NETWORK || 'localnet';
    let nonce = 0;
    let packageId;
    let gateway;
    let discovery;
    const gatewayInfo = {};
    const discoveryInfo = {};

    function calculateNextSigners() {
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

        await publishPackage(client, deployer, 'utils');
        await publishPackage(client, deployer, 'version_control');
        let result = await publishPackage(client, deployer, 'axelar_gateway');
        packageId = result.packageId;
        const creatorCap = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${packageId}::gateway::CreatorCap`,
        ).objectId;
        result = await publishPackage(client, deployer, 'relayer_discovery');
        const discoveryPackageId = result.packageId;
        discovery = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${discoveryPackageId}::discovery::RelayerDiscovery`,
        ).objectId;

        calculateNextSigners();

        const encodedSigners = WeightedSigners.serialize(gatewayInfo.signers).toBytes();
        const builder = new TxBuilder(client);

        await builder.moveCall({
            target: `${packageId}::gateway::setup`,
            arguments: [
                creatorCap,
                operator.toSuiAddress(),
                domainSeparator,
                minimumRotationDelay,
                previousSignersRetention,
                encodedSigners,
                CLOCK_PACKAGE_ID,
            ],
        });

        result = await builder.signAndExecute(deployer);

        gateway = result.objectChanges.find((change) => change.objectType === `${packageId}::gateway::Gateway`).objectId;

        gatewayInfo.gateway = gateway;
        gatewayInfo.domainSeparator = domainSeparator;
        gatewayInfo.packageId = packageId;
        discoveryInfo.packageId = discoveryPackageId;
        discoveryInfo.discovery = discovery;
    });

    describe('Signer Rotation', () => {
        it('should rotate signers', async () => {
            await sleep(2000);
            const proofSigners = gatewayInfo.signers;
            const proofKeys = gatewayInfo.signerKeys;
            calculateNextSigners();

            const encodedSigners = WeightedSigners.serialize(gatewayInfo.signers).toBytes();

            const hashed = hashMessage(encodedSigners, COMMAND_TYPE_ROTATE_SIGNERS);

            const message = MessageToSign.serialize({
                domain_separator: domainSeparator,
                signers_hash: keccak256(WeightedSigners.serialize(proofSigners).toBytes()),
                data_hash: hashed,
            }).toBytes();

            const signatures = signMessage(proofKeys.slice(0, proofSigners.threshold), message);
            const encodedProof = Proof.serialize({
                signers: proofSigners,
                signatures,
            }).toBytes();

            const builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${packageId}::gateway::rotate_signers`,
                arguments: [gateway, CLOCK_PACKAGE_ID, encodedSigners, encodedProof],
            });

            await builder.signAndExecute(keypair);
        });

        it('Should not rotate to empty signers', async () => {
            await sleep(2000);
            const proofSigners = gatewayInfo.signers;
            const proofKeys = gatewayInfo.signerKeys;

            const encodedSigners = WeightedSigners.serialize({
                signers: [],
                threshold: 2,
                nonce: hexlify([nonce + 1]),
            }).toBytes();

            const hashed = hashMessage(encodedSigners, COMMAND_TYPE_ROTATE_SIGNERS);

            const message = MessageToSign.serialize({
                domain_separator: domainSeparator,
                signers_hash: keccak256(WeightedSigners.serialize(proofSigners).toBytes()),
                data_hash: hashed,
            }).toBytes();

            const signatures = signMessage(proofKeys, message);
            const encodedProof = Proof.serialize({
                signers: proofSigners,
                signatures,
            }).toBytes();

            const builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${packageId}::gateway::rotate_signers`,
                arguments: [gateway, CLOCK_PACKAGE_ID, encodedSigners, encodedProof],
            });

            await expectRevert(builder, keypair, {
                packageId,
                module: 'weighted_signers',
                function: 'peel',
                code: 0,
            });
        });
    });

    describe('Send Message', () => {
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

        it('should send a message', async () => {
            const destinationChain = 'Destination Chain';
            const destinationAddress = 'Destination Address';
            const payload = '0x1234';
            const builder = new TxBuilder(client);

            const messageTicket = await builder.moveCall({
                target: `${packageId}::gateway::prepare_message`,
                arguments: [channel, destinationChain, destinationAddress, payload],
                typeArguments: [],
            });

            await builder.moveCall({
                target: `${packageId}::gateway::send_message`,
                arguments: [gateway, messageTicket],
                typeArguments: [],
            });

            await expectEvent(builder, keypair, {
                type: `${packageId}::events::ContractCall`,
                arguments: {
                    destination_address: destinationAddress,
                    destination_chain: destinationChain,
                    payload: arrayify(payload),
                    payload_hash: keccak256(payload),
                    source_id: channel,
                },
            });
        });

        it('should approve a message', async () => {
            const message = {
                source_chain: 'Ethereum',
                message_id: 'Message Id',
                source_address: 'Source Address',
                destination_id: keccak256(defaultAbiCoder.encode(['string'], ['destination'])),
                payload_hash: keccak256(defaultAbiCoder.encode(['string'], ['payload hash'])),
            };

            await approveMessage(client, keypair, gatewayInfo, message);

            const builder = new TxBuilder(client);

            const payloadHash = await builder.moveCall({
                target: `${packageId}::bytes32::new`,
                arguments: [message.payload_hash],
            });

            await builder.moveCall({
                target: `${packageId}::gateway::is_message_approved`,
                arguments: [gateway, message.source_chain, message.message_id, message.source_address, message.destination_id, payloadHash],
            });

            await builder.moveCall({
                target: `${packageId}::gateway::is_message_executed`,
                arguments: [gateway, message.source_chain, message.message_id],
            });

            const resp = await builder.devInspect(keypair.toSuiAddress());

            expect(bcs.Bool.parse(new Uint8Array(resp.results[1].returnValues[0][0]))).to.equal(true);
            expect(bcs.Bool.parse(new Uint8Array(resp.results[2].returnValues[0][0]))).to.equal(false);
        });

        it('should execute a message', async () => {
            await publishPackage(client, keypair, 'gas_service');
            await publishPackage(client, keypair, 'abi');
            await publishPackage(client, keypair, 'governance');
            await publishPackage(client, keypair, 'its');
            const result = await publishPackage(client, keypair, 'example');

            const testId = result.packageId;
            const singleton = result.publishTxn.objectChanges.find((change) => change.objectType === `${testId}::gmp::Singleton`).objectId;
            const sinlgetonData = await client.getObject({
                id: singleton,
                options: {
                    showContent: true,
                },
            });

            const channelId = sinlgetonData.data.content.fields.channel.fields.id.id;

            let builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${testId}::gmp::register_transaction`,
                arguments: [discovery, singleton],
            });

            await builder.signAndExecute(keypair);

            const payload = '0x0123';
            const message = {
                source_chain: 'Ethereum',
                message_id: 'Message Id 2',
                source_address: 'Source Address',
                destination_id: channelId,
                payload,
                payload_hash: keccak256(payload),
            };

            let resp = await approveAndExecute(client, keypair, gatewayInfo, discoveryInfo, message, { showEvents: true });

            const event = resp.events.find((event) => event.type === `${testId}::gmp::Executed`);

            expect(event.parsedJson.payload === message.payload);

            builder = new TxBuilder(client);

            const payloadHash = await builder.moveCall({
                target: `${packageId}::bytes32::new`,
                arguments: [message.payload_hash],
            });

            await builder.moveCall({
                target: `${packageId}::gateway::is_message_approved`,
                arguments: [gateway, message.source_chain, message.message_id, message.source_address, message.destination_id, payloadHash],
            });

            await builder.moveCall({
                target: `${packageId}::gateway::is_message_executed`,
                arguments: [gateway, message.source_chain, message.message_id],
            });

            resp = await builder.devInspect(keypair.toSuiAddress());

            expect(bcs.Bool.parse(new Uint8Array(resp.results[1].returnValues[0][0]))).to.equal(false);
            expect(bcs.Bool.parse(new Uint8Array(resp.results[2].returnValues[0][0]))).to.equal(true);
        });
    });
});
