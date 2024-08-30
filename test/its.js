const { SuiClient, getFullnodeUrl } = require('@mysten/sui/client');
const { Ed25519Keypair } = require('@mysten/sui/keypairs/ed25519');
const { Secp256k1Keypair } = require('@mysten/sui/keypairs/secp256k1');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui/faucet');
const {
    publishPackage,
    getRandomBytes32,
    expectRevert,
    expectEvent,
    approveMessage,
    hashMessage,
    signMessage,
    approveAndExecuteMessage,
} = require('./utils');
const { TxBuilder } = require('../dist/tx-builder');
const {
    bcsStructs: {
        gateway: { WeightedSigners, MessageToSign, Proof },
    },
} = require('../dist/bcs');
const { bcs } = require('@mysten/sui/bcs');
const { arrayify, hexlify, keccak256, defaultAbiCoder } = require('ethers/lib/utils');
const { expect } = require('chai');

const COMMAND_TYPE_ROTATE_SIGNERS = 1;
const clock = '0x6';
const sui = '0x2';
const MESSAGE_TYPE_SET_TRUSTED_ADDRESSES = BigInt(0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68);

describe.only('ITS', () => {
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
    let its;
    let axelarPackageId;
    let gasService, gasServicePackageId;
    let exampleId, singleton;
    let governance;
    const remoteChain = 'Remote Chain';
    const trustedAddress = 'Trusted Address';
    const gatewayInfo = {};

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

    async function newExample() {
        const result = await publishPackage(client, keypair, 'example');
        exampleId = result.packageId;
        singleton = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${exampleId}::its_example::Singleton`,
        ).objectId;
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
        axelarPackageId = result.packageId;
        const creatorCap = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${axelarPackageId}::gateway::CreatorCap`,
        ).objectId;
        discovery = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${axelarPackageId}::discovery::RelayerDiscovery`,
        ).objectId;

        result = await publishPackage(client, deployer, 'gas_service');
        gasServicePackageId = result.packageId;
        gasService = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${gasServicePackageId}::gas_service::GasService`,
        ).objectId;

        await publishPackage(client, deployer, 'abi');
        result  = await publishPackage(client, deployer, 'governance');
        const governanceId = result.packageId;
        const governanceUpgradeCap = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${sui}::package::UpgradeCap`,
        ).objectId;

        result = await publishPackage(client, deployer, 'its');
        packageId = result.packageId;
        its = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${packageId}::its::ITS`,
        ).objectId;

        calculateNextSigners();

        const encodedSigners = WeightedSigners.serialize(gatewayInfo.signers).toBytes();
        let builder = new TxBuilder(client);

        const separator = await builder.moveCall({
            target: `${axelarPackageId}::bytes32::new`,
            arguments: [domainSeparator],
        });

        await builder.moveCall({
            target: `${axelarPackageId}::gateway::setup`,
            arguments: [
                creatorCap,
                operator.toSuiAddress(),
                separator,
                minimumRotationDelay,
                previousSignersRetention,
                encodedSigners,
                clock,
            ],
        });

        const trustedSourceChain = 'Axelar';
        const trustedSourceAddress = 'Address';
        const messageType = 1234;
        await builder.moveCall({
            target: `${governanceId}::governance::new`,
            arguments: [
                trustedSourceChain,
                trustedSourceAddress,
                messageType,
                governanceUpgradeCap,
            ],
        })

        result = await builder.signAndExecute(deployer);
        gateway = result.objectChanges.find((change) => change.objectType === `${axelarPackageId}::gateway::Gateway`).objectId;
        governance = result.objectChanges.find((change) => change.objectType === `${governanceId}::governance::Governance`).objectId;

        gatewayInfo.gateway = gateway;
        gatewayInfo.domainSeparator = domainSeparator;
        gatewayInfo.packageId = axelarPackageId;
        gatewayInfo.discovery = discovery;

        const itsData = await client.getObject({
            id: its,
            options: {
                showContent: true,
            },
        });

        const channelId = itsData.data.content.fields.channel.fields.id.id;

        const payload = defaultAbiCoder.encode(['uint256', 'bytes'], [
            MESSAGE_TYPE_SET_TRUSTED_ADDRESSES,
            bcs.struct('Trusted Addresses', {
                chain_names: bcs.vector(bcs.String),
                trusted_addresses: bcs.vector(bcs.String),
            }).serialize({
                chain_names: [remoteChain],
                trusted_addresses: [trustedAddress],
            }).toBytes(),
        ]);
        const message = {
            source_chain: trustedSourceAddress,
            message_id: 'Message Id 0',
            source_address: trustedSourceAddress,
            destination_id: channelId,
            payload,
            payload_hash: keccak256(payload),
        };

        await approveMessage(client, keypair, gatewayInfo, message);
        builder = new TxBuilder(client);

        const approvedMessage = await builder.moveCall({
            target: `${axelarPackageId}::gateway::take_approved_message`,
            arguments: [
                gateway,
                message.source_chain,
                message.message_id,
                message.source_address,
                message.destination_id,
                message.payload,
            ],
        });

        await builder.moveCall({
            target: `${packageId}::service::set_trusted_addresses`,
            arguments: [
                its,
                governance,
                approvedMessage,
            ],
        });

        await builder.signAndExecute(keypair);
    });

    describe('Token Registration', () => {
        it('Should register a coin', async () => {
            await newExample();

            let builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${exampleId}::its_example::register_coin`,
                arguments: [
                    singleton,
                    its,
                ],
                typeArguments: [],
            });
            
            await expectEvent(builder, keypair, {
                type: `${packageId}::service::CoinRegistered`
            });
        });
    });

    describe('Its Example', () => {
        it('Should register a coin', async () => {
            await newExample();

            let builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${exampleId}::its_example::register_coin`,
                arguments: [
                    singleton,
                    its,
                ],
                typeArguments: [],
            });
            
            await expectEvent(builder, keypair, {
                type: `${packageId}::service::CoinRegistered`
            });
        });

        it('Should send some tokens', async () => {
            const amount = 1234;
            await newExample();

            let builder = new TxBuilder(client);

            const coin = await builder.moveCall({
                target: `${exampleId}::its_example::mint`,
                arguments: [
                    singleton,
                    amount,
                ],
                typeArguments: [],
            });
            await builder.moveCall({
                target: `${exampleId}::its_example::register_coin`,
                arguments: [
                    singleton,
                    its,
                ],
                typeArguments: [],
            });
            const gas = await builder.moveCall({
                target: `${sui}::coin::zero`,
                arguments: [],
                typeArguments: [
                    `${sui}::sui::SUI`
                ],
            }); 
            await builder.moveCall({
                target: `${exampleId}::its_example::send_interchain_transfer`,
                arguments: [
                    singleton, 
                    its,
                    'Destination Chain', 
                    '0x1234', 
                    coin,
                    '0x',
                    gasService, 
                    gas, 
                    '0x6',
                ],
                typeArguments: [],
            });
            
            await expectEvent(builder, keypair, {
                type: `${packageId}::service::CoinRegistered`
            });
        });
    });
});
