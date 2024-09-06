const { SuiClient, getFullnodeUrl } = require('@mysten/sui/client');
const { Ed25519Keypair } = require('@mysten/sui/keypairs/ed25519');
const { Secp256k1Keypair } = require('@mysten/sui/keypairs/secp256k1');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui/faucet');
const { publishPackage, getRandomBytes32, expectEvent, approveMessage } = require('./utils');
const { TxBuilder } = require('../dist/tx-builder');
const {
    bcsStructs: {
        gateway: { WeightedSigners },
    },
} = require('../dist/bcs');
const { bcs } = require('@mysten/sui/bcs');
const {
    utils: { arrayify, hexlify, keccak256, defaultAbiCoder },
    constants: { HashZero },
} = require('ethers');

const clock = '0x6';
const sui = '0x2';
const MESSAGE_TYPE_SET_TRUSTED_ADDRESSES = '0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68';
// This is because of a discrepancy between decimals and remote decimals;
const multiplier = 10000;

describe('ITS', () => {
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
    let exampleId, singleton, singletonChannel;
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
        singleton = result.publishTxn.objectChanges.find((change) => change.objectType === `${exampleId}::its_example::Singleton`).objectId;

        const singletonData = await client.getObject({
            id: singleton,
            options: {
                showContent: true,
            },
        });

        singletonChannel = singletonData.data.content.fields.channel.fields.id.id;
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

        await publishPackage(client, deployer, 'abi');
        await publishPackage(client, deployer, 'gas_service');
        result = await publishPackage(client, deployer, 'governance');
        const governanceId = result.packageId;
        const governanceUpgradeCap = result.publishTxn.objectChanges.find(
            (change) => change.objectType === `${sui}::package::UpgradeCap`,
        ).objectId;

        result = await publishPackage(client, deployer, 'its');
        packageId = result.packageId;
        its = result.publishTxn.objectChanges.find((change) => change.objectType === `${packageId}::its::ITS`).objectId;

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
            arguments: [trustedSourceChain, trustedSourceAddress, messageType, governanceUpgradeCap],
        });

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

        const payload = defaultAbiCoder.encode(
            ['bytes32', 'bytes'],
            [
                MESSAGE_TYPE_SET_TRUSTED_ADDRESSES,
                bcs
                    .struct('Trusted Addresses', {
                        chain_names: bcs.vector(bcs.String),
                        trusted_addresses: bcs.vector(bcs.String),
                    })
                    .serialize({
                        chain_names: [remoteChain],
                        trusted_addresses: [trustedAddress],
                    })
                    .toBytes(),
            ],
        );
        const message = {
            source_chain: trustedSourceChain,
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
            arguments: [gateway, message.source_chain, message.message_id, message.source_address, message.destination_id, message.payload],
        });

        await builder.moveCall({
            target: `${packageId}::service::set_trusted_addresses`,
            arguments: [its, governance, approvedMessage],
        });

        await builder.signAndExecute(keypair);
    });

    describe('Its Example', () => {
        it('Should register a coin', async () => {
            await newExample();

            const builder = new TxBuilder(client);

            await builder.moveCall({
                target: `${exampleId}::its_example::register_coin`,
                arguments: [singleton, its],
                typeArguments: [],
            });

            await expectEvent(builder, keypair, {
                type: `${packageId}::service::CoinRegistered<${exampleId}::its_example::ITS_EXAMPLE>`,
            });
        });

        it('Should send some tokens', async () => {
            const amount = 1234;
            const destinationAddress = '0x1234';
            await newExample();

            const builder = new TxBuilder(client);

            const coin = await builder.moveCall({
                target: `${exampleId}::its_example::mint`,
                arguments: [singleton, amount],
                typeArguments: [],
            });
            await builder.moveCall({
                target: `${exampleId}::its_example::register_coin`,
                arguments: [singleton, its],
                typeArguments: [],
            });
            await builder.moveCall({
                target: `${exampleId}::its_example::send_interchain_transfer`,
                arguments: [singleton, its, remoteChain, '0x1234', coin, '0x', clock],
                typeArguments: [],
            });
            await expectEvent(builder, keypair, {
                type: `${packageId}::service::InterchainTransfer<${exampleId}::its_example::ITS_EXAMPLE>`,
                arguments: {
                    source_address: arrayify(singletonChannel),
                    destination_chain: remoteChain,
                    destination_address: arrayify(destinationAddress),
                    amount: `${amount * multiplier}`,
                    data_hash: HashZero,
                },
            });
        });
    });
});
