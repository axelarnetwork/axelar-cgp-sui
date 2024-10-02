/*
This is a short spec for what there is to be done. You can check https://github.com/axelarnetwork/interchain-token-service/blob/main/test/InterchainTokenService.js for some details.
[x] Test deployment of interchian token service.
[x] Test `register_transaction` (this tells relayers how to execute contract calls).
[x] Test owner functions (mint/burn).
[x] Test public functions (`register_token` etc.).
[x] Write an ITS example.
[x] Use the ITS example for end to end tests.
*/
const { SuiClient, getFullnodeUrl } = require('@mysten/sui/client');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui/faucet');
const {
    publishPackage,
    clock,
    generateEd25519Keypairs,
    findObjectId,
    getRandomBytes32,
    calculateNextSigners,
    approveMessage,
    getSingletonChannelId,
    setupITSTrustedAddresses,
} = require('./testutils');
const { expect } = require('chai');
const { bcsStructs } = require('../dist/bcs');
const { TxBuilder } = require('../dist/tx-builder');
const { keccak256, defaultAbiCoder, toUtf8Bytes, hexlify, randomBytes } = require('ethers/lib/utils');

describe('ITS', () => {
    // Sui Client
    let client;
    const network = process.env.NETWORK || 'localnet';

    // Store the deployed packages info
    const deployments = {};

    // Store the object ids from move transactions
    const objectIds = {};

    // A list of contracts to publish
    const dependencies = [
        'utils',
        'version_control',
        'gas_service',
        'abi',
        'axelar_gateway',
        'relayer_discovery',
        'governance',
        'its',
        'example',
    ];

    // Parameters for Gateway Setup
    const gatewayInfo = {};
    const domainSeparator = getRandomBytes32();
    const [operator, deployer, keypair] = generateEd25519Keypairs(3);
    const minimumRotationDelay = 1000;
    const previousSignersRetention = 15;
    const nonce = 0;

    // Parameters for Trusted Addresses
    const trustedSourceChain = 'Avalanche';
    const trustedSourceAddress = hexlify(randomBytes(20));

    async function setupGovernance() {
        // Parameters for Governance Setup
        const governanceSourceChain = 'Axelar';
        const governanceSourceAddress = 'Governance Source Address';
        const governanceMessageType = BigInt('0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68');

        const governanceSetupTxBuilder = new TxBuilder(client);
        await governanceSetupTxBuilder.moveCall({
            target: `${deployments.governance.packageId}::governance::new`,
            arguments: [governanceSourceChain, governanceSourceAddress, governanceMessageType, objectIds.upgradeCap],
        });
        const receipt = await governanceSetupTxBuilder.signAndExecute(deployer);

        objectIds.governance = findObjectId(receipt, 'governance::Governance');
    }

    async function setupGateway() {
        calculateNextSigners(gatewayInfo, nonce);
        const encodedSigners = bcsStructs.gateway.WeightedSigners.serialize(gatewayInfo.signers).toBytes();

        const gatewaySetupTxBuilder = new TxBuilder(client);

        await gatewaySetupTxBuilder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::gateway::setup`,
            arguments: [
                objectIds.creatorCap,
                operator.toSuiAddress(),
                domainSeparator,
                minimumRotationDelay,
                previousSignersRetention,
                encodedSigners,
                clock,
            ],
        });

        const gatewaySetupReceipt = await gatewaySetupTxBuilder.signAndExecute(deployer);

        objectIds.gateway = findObjectId(gatewaySetupReceipt, 'gateway::Gateway');

        gatewayInfo.gateway = objectIds.gateway;
        gatewayInfo.domainSeparator = domainSeparator;
        gatewayInfo.packageId = deployments.axelar_gateway.packageId;
    }

    before(async () => {
        client = new SuiClient({ url: getFullnodeUrl(network) });

        // Request funds from faucet
        await Promise.all(
            [operator, deployer, keypair].map((keypair) =>
                requestSuiFromFaucetV0({
                    host: getFaucetHost(network),
                    recipient: keypair.toSuiAddress(),
                }),
            ),
        );

        // Publish all packages
        for (const packageName of dependencies) {
            const result = await publishPackage(client, deployer, packageName);

            deployments[packageName] = result;
        }

        // Find the object ids from the publish transactions
        objectIds.its = findObjectId(deployments.its.publishTxn, 'ITS');
        objectIds.singleton = findObjectId(deployments.example.publishTxn, 'its_example::Singleton');
        objectIds.relayerDiscovery = findObjectId(deployments.relayer_discovery.publishTxn, 'RelayerDiscovery');
        objectIds.gasService = findObjectId(deployments.gas_service.publishTxn, 'GasService');
        objectIds.upgradeCap = findObjectId(deployments.governance.publishTxn, 'UpgradeCap');
        objectIds.creatorCap = findObjectId(deployments.axelar_gateway.publishTxn, 'CreatorCap');

        // Mint some coins for tests
        const tokenTxBuilder = new TxBuilder(client);

        await tokenTxBuilder.moveCall({
            target: `${deployments.example.packageId}::its_example::mint`,
            arguments: [objectIds.singleton, 1e18, deployer.toSuiAddress()],
        });

        const mintReceipt = await tokenTxBuilder.signAndExecute(deployer);

        // Find the coin object id
        objectIds.coin = findObjectId(mintReceipt, 'its_example::ITS_EXAMPLE');

        await setupGateway();

        await setupGovernance();

        objectIds.itsChannel = await getSingletonChannelId(client, objectIds.its);

        // Setup Trusted Addresses
        await setupITSTrustedAddresses(client, keypair, gatewayInfo, objectIds, deployments, [trustedSourceAddress], [trustedSourceChain]);
    });

    it('should call register_transaction successfully', async () => {
        const txb = new TxBuilder(client);

        await txb.moveCall({
            target: `${deployments.example.packageId}::its_example::register_transaction`,
            arguments: [objectIds.relayerDiscovery, objectIds.singleton, objectIds.its, clock],
        });

        const txResult = await txb.signAndExecute(deployer);

        const discoveryTx = findObjectId(txResult, 'discovery::Transaction');
        expect(discoveryTx).to.be.not.null;
    });

    it('should register a coin successfully', async () => {
        const txb = new TxBuilder(client);
        await txb.moveCall({
            target: `${deployments.example.packageId}::its_example::register_coin`,
            arguments: [objectIds.singleton, objectIds.its],
        });

        const txResult = await txb.signAndExecute(deployer, {
            showEvents: true,
        });

        objectIds.tokenId = txResult.events[0].parsedJson.token_id.id;

        expect(txResult.events.length).to.equal(1);
        expect(objectIds.tokenId).to.be.not.null;
    });

    describe('Interchain Transfer', () => {
        it('should send interchain transfer successfully', async () => {
            // Send interchain transfer
            const txb = new TxBuilder(client);

            const tx = txb.tx;

            const coin = tx.splitCoins(objectIds.coin, [1e9]);
            const gas = tx.splitCoins(tx.gas, [1e8]);

            const TokenId = await txb.moveCall({
                target: `${deployments.its.packageId}::token_id::from_u256`,
                arguments: [objectIds.tokenId],
            });

            await txb.moveCall({
                target: `${deployments.example.packageId}::its_example::send_interchain_transfer_call`,
                arguments: [
                    objectIds.singleton,
                    objectIds.its,
                    objectIds.gateway,
                    objectIds.gasService,
                    TokenId,
                    coin,
                    trustedSourceChain,
                    trustedSourceAddress,
                    '0x', // its token metadata
                    deployer.toSuiAddress(),
                    gas,
                    '0x', // gas params
                    clock,
                ],
            });

            await txb.signAndExecute(deployer);
        });

        // This test depends on the previous one because it needs to have fund transferred to the coin_management contract beforehand.
        it('should receive interchain transfer successfully', async () => {
            // Approve ITS transfer message
            const messageType = 0; // MESSAGE_TYPE_INTERCHAIN_TRANSFER
            const tokenId = objectIds.tokenId; // The token ID to transfer
            const sourceAddress = trustedSourceAddress; // Previously set as trusted address
            const destinationAddress = objectIds.itsChannel; // The ITS Channel ID. All ITS messages are sent to this channel
            const amount = 1e9; // An amount to transfer
            const data = '0x1234'; // Random data

            // Channel ID for the ITS example. This will be encoded in the payload
            const itsExampleChannelId = await getSingletonChannelId(client, objectIds.singleton);

            // ITS transfer payload from Ethereum to Sui
            const payload = defaultAbiCoder.encode(
                ['uint256', 'uint256', 'bytes', 'bytes', 'uint256', 'bytes'],
                [messageType, tokenId, sourceAddress, itsExampleChannelId, amount, data],
            );

            const message = {
                source_chain: trustedSourceChain,
                message_id: hexlify(randomBytes(32)),
                source_address: trustedSourceAddress,
                destination_id: destinationAddress,
                payload_hash: keccak256(payload),
            };

            await approveMessage(client, keypair, gatewayInfo, message);

            const txb = new TxBuilder(client);

            const approvedMessage = await txb.moveCall({
                target: `${deployments.axelar_gateway.packageId}::gateway::take_approved_message`,
                arguments: [
                    objectIds.gateway,
                    message.source_chain,
                    message.message_id,
                    message.source_address,
                    message.destination_id,
                    payload,
                ],
            });

            await txb.moveCall({
                target: `${deployments.example.packageId}::its_example::receive_interchain_transfer`,
                arguments: [approvedMessage, objectIds.singleton, objectIds.its, clock],
            });

            await txb.signAndExecute(deployer);
        });
    });

    describe('Deploy Interchain Token', () => {
        it('should deploy remote interchain token to other chain successfully', async () => {
            const txb = new TxBuilder(client);

            const tx = txb.tx;
            const gas = tx.splitCoins(tx.gas, [1e8]);

            const TokenId = await txb.moveCall({
                target: `${deployments.its.packageId}::token_id::from_u256`,
                arguments: [objectIds.tokenId],
            });

            await txb.moveCall({
                target: `${deployments.example.packageId}::its_example::deploy_remote_interchain_token`,
                arguments: [
                    objectIds.its,
                    objectIds.gateway,
                    objectIds.gasService,
                    trustedSourceChain,
                    TokenId,
                    gas,
                    '0x',
                    deployer.toSuiAddress(),
                ],
            });

            await txb.signAndExecute(deployer);
        });

        it('should receive interchain token deployment from other chain successfully', async () => {
            // Deploy the interchain token and store object ids for treasury cap and metadata
            const publishReceipt = await publishPackage(client, deployer, 'interchain_token');
            const treasuryCap = findObjectId(publishReceipt.publishTxn, 'TreasuryCap');
            const metadata = findObjectId(publishReceipt.publishTxn, 'CoinMetadata');

            // Approve ITS transfer message
            const messageType = 1; // MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN
            const tokenId = hexlify(randomBytes(32)); // The token ID to transfer
            const name = toUtf8Bytes('Quote');
            const symbol = toUtf8Bytes('Q');
            const decimals = 9;
            const distributor = '0x';

            // ITS transfer payload from Ethereum to Sui
            const payload = defaultAbiCoder.encode(
                ['uint256', 'uint256', 'bytes', 'bytes', 'uint256', 'bytes'],
                [messageType, tokenId, name, symbol, decimals, distributor],
            );

            const message = {
                source_chain: trustedSourceChain,
                message_id: hexlify(randomBytes(32)),
                source_address: trustedSourceAddress,
                destination_id: objectIds.itsChannel,
                payload_hash: keccak256(payload),
            };

            await approveMessage(client, keypair, gatewayInfo, message);

            const txb = new TxBuilder(client);

            const approvedMessage = await txb.moveCall({
                target: `${deployments.axelar_gateway.packageId}::gateway::take_approved_message`,
                arguments: [
                    objectIds.gateway,
                    message.source_chain,
                    message.message_id,
                    message.source_address,
                    message.destination_id,
                    payload,
                ],
            });

            txb.moveCall({
                target: `${deployments.its.packageId}::service::give_unregistered_coin`,
                arguments: [objectIds.its, treasuryCap, metadata],
                typeArguments: [`${publishReceipt.packageId}::q::Q`],
            });

            await txb.moveCall({
                target: `${deployments.its.packageId}::service::receive_deploy_interchain_token`,
                arguments: [objectIds.its, approvedMessage],
                typeArguments: [`${publishReceipt.packageId}::q::Q`],
            });

            await txb.signAndExecute(deployer);
        });
    });
});
