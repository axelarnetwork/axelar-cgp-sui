const { SuiClient, getFullnodeUrl } = require('@mysten/sui/client');
const { Ed25519Keypair } = require('@mysten/sui/keypairs/ed25519');
const { Secp256k1Keypair } = require('@mysten/sui/keypairs/secp256k1');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui/faucet');
const { publishPackage, getRandomBytes32, approveMessage, hashMessage, signMessage, findObjectId } = require('../test/testutils');
const { TxBuilder, CLOCK_PACKAGE_ID } = require('../dist/cjs');
const {
    bcsStructs: {
        gateway: { WeightedSigners, MessageToSign, Proof, Message },
    },
} = require('../dist/cjs/bcs');
const { arrayify, hexlify, keccak256, defaultAbiCoder } = require('ethers/lib/utils');
const { bcs } = require('@mysten/sui/bcs');

async function main() {
    const COMMAND_TYPE_APPROVE_MESSAGES = 0;
    const COMMAND_TYPE_ROTATE_SIGNERS = 1;

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
    let gatewayInfo = {};
    const discoveryInfo = {};

    function calculateNextSigners(n = 3, threshold = 2) {
        signerKeys = Array.from({length: n}, getRandomBytes32);
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
        return {
            signerKeys: keys.map((key) => key.privKey),
            signers: {
                signers: keys.map((key) => {
                    return { pub_key: key.pubKey, weight: 1 };
                }),
                threshold,
                nonce: hexlify([++nonce]),
            },
        }
    }

    async function rotateSigners(n = 3, threshold = 2) {console.log(n, threshold);
        let proofSigners = gatewayInfo.signers;
        let proofKeys = gatewayInfo.signerKeys;
        let nextSigners = calculateNextSigners(n, threshold);

        const encodedSigners = WeightedSigners.serialize(nextSigners.signers).toBytes();

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
        gatewayInfo = {
            ...gatewayInfo,
            ...nextSigners,
        };
        console.log(gatewayInfo, nextSigners);
    }

    // Perform a binary search to find the maximum possible balue of n before testFn(n) fails.
    async function binarySearch(testFn, min = 1, max = 10000) {
        if(max === min + 1) return min
        while(max - min > 1) {
            const mid = Math.floor((min + max)/2);
            try {
                await testFn(mid);
                console.log(`${mid}: success.`);
                min = mid;
            } catch(e) {
                console.log(`${mid}: failure.`);
                console.log(e);
                max = mid;
            }
        }
        return min;
    }

    async function sleep(ms = 1000) {
        await new Promise((resolve) => setTimeout(resolve, ms));
    }

    const minimumRotationDelay = 1000;
    const previousSignersRetention = 15;

    async function getMaxSigners() {
        await sleep(2000);
        return await binarySearch(rotateSigners);
    }

    // This does not work properly because once you rotate to a signer set that cannot sign you are locked out of the gateway.
    async function getMaxSignatures() {
        await sleep(2000);

        return await binarySearch(async (n) => {
            await rotateSigners(n, n);
            let proofSigners = gatewayInfo.signers;
            let proofKeys = gatewayInfo.signerKeys;

            const contractCallInfo = {
                source_chain: 'Ethereum',
                message_id: 'Message Id',
                source_address: 'Source Address',
                destination_id: keccak256(defaultAbiCoder.encode(['string'], ['destination'])),
                payload_hash: keccak256(defaultAbiCoder.encode(['string'], ['payload hash'])),
            };

            const messageData = bcs.vector(Message).serialize([contractCallInfo]).toBytes();

            const hashed = hashMessage(messageData, COMMAND_TYPE_APPROVE_MESSAGES);

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
                target: `${packageId}::gateway::approve_messages`,
                arguments: [gateway, messageData, encodedProof],
            });
            await builder.signAndExecute(keypair);
        }, 2, 200);
    }

    async function getMaxMessageSize() {

        const builder = new TxBuilder(client);

        const channelObj = await builder.moveCall({
            target: `${packageId}::channel::new`,
            arguments: [],
        });

        builder.tx.transferObjects([channelObj], keypair.toSuiAddress());

        const response = await builder.signAndExecute(keypair);

        const channel = findObjectId(response, 'channel::Channel');

        return await binarySearch(async (n) => {
            const payload = new Uint8Array(n);

            const builder = new TxBuilder(client);

            const message = await builder.moveCall({
                target: `${packageId}::gateway::prepare_message`,
                arguments: [
                    channel,
                    'destination_chain',
                    'destination_address',
                    payload,
                ]
            });

            await builder.moveCall({
                target: `${packageId}::gateway::send_message`,
                arguments: [
                    gateway,
                    message,
                ]
            });

            await builder.signAndExecute(keypair);
        }, 1000, 1000000);
    }

    async function getMaxApprovals() {
        const message = {
            source_chain: 'Ethereum',
            source_address: 'Source Address',
            destination_id: keccak256(defaultAbiCoder.encode(['string'], ['destination'])),
            payload_hash: keccak256(defaultAbiCoder.encode(['string'], ['payload hash'])),
        };

        return await binarySearch(async (n) => {
            const messages = Array.from({length: n}, (_, index) => {
                return {
                    message_id: getRandomBytes32(),
                    ...message,
                }
            });
            await approveMessage(client, keypair, gatewayInfo, messages);
        });
    }

    async function prepare() {
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

        gatewayInfo = {
            ...calculateNextSigners(),
            ... gatewayInfo,
        }; 

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
    }

    await prepare();
    const maxApprovals = await getMaxApprovals();
    const maxSigners = await getMaxSigners();
    const messageSize = await getMaxMessageSize();
    const maxSignatures = await getMaxSignatures();
    console.log("<details>");
    console.log("  <summary>Click to see the limis</summary>")
    console.log(`Maximum possible approvals in a call: ${maxApprovals}\n`);
    console.log(`Maximum possible signers in a signer set: ${maxSigners}\n`);
    console.log(`Maximum message size: ${messageSize}\n`);
    console.log(`Maximum Signatures: ${maxSignatures}\n`);
    console.log("</details>");
}

main();



