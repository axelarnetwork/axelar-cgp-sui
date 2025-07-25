/*
This is a short spec for what there is to be done. You can check https://github.com/axelarnetwork/interchain-token-service/blob/main/test/InterchainTokenService.js for some details.
Note that this test suite uses the example Move contract in some cases (`/move/example`), and the production 
move contract in other cases (`/move/interchain_token_service`). 

TODO: move the example contract tests to their own test file (example.js), and keep this test file for ITS tests

[x] Test deployment of interchain token service.
[x] Test `register_transaction` (this tells relayers how to execute contract calls).
[x] Test owner functions (mint/burn).
[x] Test public functions (`register_coin` etc.).
[x] Write an ITS example.
[x] Use the ITS example for end to end tests.
*/
const { SuiClient, getFullnodeUrl } = require('@mysten/sui/client');
const {
    publishPackage,
    publishInterchainToken,
    generateEd25519Keypairs,
    findObjectId,
    getRandomBytes32,
    calculateNextSigners,
    getSingletonChannelId,
    setupTrustedAddresses,
    getVersionedChannelId,
} = require('./testutils');
const { expect } = require('chai');
const {
    CLOCK_PACKAGE_ID,
    fundAccountsFromFaucet,
    getDeploymentOrder,
    approveAndExecute,
    bcsStructs,
    ITSMessageType,
    TxBuilder,
} = require('../dist/cjs');
const { keccak256, defaultAbiCoder, toUtf8Bytes, hexlify, randomBytes, arrayify } = require('ethers/lib/utils');
const { bcs } = require('@mysten/sui/bcs');

describe('ITS', () => {
    // Sui Client
    let client;
    const network = process.env.NETWORK || 'localnet';

    // Store the deployed packages info
    const deployments = {};

    // Store the object ids from move transactions
    let objectIds = {};

    // A list of contracts to publish
    const dependencies = getDeploymentOrder('example', `${__dirname}/../move`);
    // should be ['version_control', 'utils', 'axelar_gateway', 'gas_service', 'abi', 'governance', 'relayer_discovery', 'its', 'example']

    // Parameters for Gateway Setup
    const gatewayInfo = {};
    const discoveryInfo = {};
    const domainSeparator = getRandomBytes32();
    const [operator, deployer, keypair] = generateEd25519Keypairs(3);
    const minimumRotationDelay = 1000;
    const previousSignersRetention = 15;
    const nonce = 0;

    // Parameters for Trusted Addresses
    const trustedSourceChain = 'axelar';
    const trustedSourceAddress = 'hub_address';
    const otherChain = 'Avalanche';
    const chainName = 'Chain Name';

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
                CLOCK_PACKAGE_ID,
            ],
        });

        const gatewaySetupReceipt = await gatewaySetupTxBuilder.signAndExecute(deployer);

        objectIds.gateway = findObjectId(gatewaySetupReceipt, 'gateway::Gateway');

        gatewayInfo.gateway = objectIds.gateway;
        gatewayInfo.domainSeparator = domainSeparator;
        gatewayInfo.packageId = deployments.axelar_gateway.packageId;
        discoveryInfo.packageId = deployments.relayer_discovery.packageId;
        discoveryInfo.discovery = objectIds.relayerDiscovery;
    }

    async function setupIts() {
        const itsSetupTxBuilder = new TxBuilder(client);

        await itsSetupTxBuilder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::interchain_token_service::setup`,
            arguments: [objectIds.itsCreatorCap, chainName, trustedSourceAddress],
        });

        const itsSetupReceipt = await itsSetupTxBuilder.signAndExecute(deployer);

        objectIds.its = findObjectId(itsSetupReceipt, 'interchain_token_service::InterchainTokenService');
        objectIds.itsV0 = findObjectId(itsSetupReceipt, 'interchain_token_service_v0::InterchainTokenService_v0');
    }

    async function registerItsTransaction() {
        const registerTransactionBuilder = new TxBuilder(client);

        await registerTransactionBuilder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::discovery::register_transaction`,
            arguments: [objectIds.its, objectIds.relayerDiscovery],
        });

        await registerTransactionBuilder.signAndExecute(deployer);
    }

    before(async () => {
        client = new SuiClient({ url: getFullnodeUrl(network) });

        // Request funds from faucet
        const addresses = [operator, deployer, keypair].map((keypair) => keypair.toSuiAddress());
        await fundAccountsFromFaucet(addresses);

        // Publish all packages
        for (const packageDir of dependencies) {
            const publishedReceipt = await publishPackage(client, deployer, packageDir);

            deployments[packageDir] = publishedReceipt;
        }

        const coinType = `${deployments.example.packageId}::token::TOKEN`;
        objectIds = {
            singleton: findObjectId(deployments.example.publishTxn, 'its::Singleton'),
            tokenTreasuryCap: findObjectId(deployments.example.publishTxn, `TreasuryCap<${coinType}>`),
            tokenCoinMetadata: findObjectId(deployments.example.publishTxn, `CoinMetadata<${coinType}>`),
            relayerDiscovery: findObjectId(
                deployments.relayer_discovery.publishTxn,
                `${deployments.relayer_discovery.packageId}::discovery::RelayerDiscovery`,
            ),
            gasService: findObjectId(deployments.gas_service.publishTxn, `${deployments.gas_service.packageId}::gas_service::GasService`),
            creatorCap: findObjectId(deployments.axelar_gateway.publishTxn, 'OwnerCap'),
            itsOwnerCap: findObjectId(
                deployments.interchain_token_service.publishTxn,
                `${deployments.interchain_token_service.packageId}::owner_cap::OwnerCap`,
            ),
            itsCreatorCap: findObjectId(
                deployments.interchain_token_service.publishTxn,
                `${deployments.interchain_token_service.packageId}::creator_cap::CreatorCap`,
            ),
        };
        // Mint some coins for tests
        const tokenTxBuilder = new TxBuilder(client);

        await tokenTxBuilder.moveCall({
            target: `${deployments.example.packageId}::token::mint`,
            arguments: [objectIds.tokenTreasuryCap, 1e18, deployer.toSuiAddress()],
        });

        const mintReceipt = await tokenTxBuilder.signAndExecute(deployer);

        await setupIts();

        // Find the object ids from the publish transactions
        objectIds = {
            ...objectIds,
            itsChannel: await getVersionedChannelId(client, objectIds.itsV0),
            token: findObjectId(mintReceipt, 'token::TOKEN'),
        };
    });

    it('should check that the unregistered token id is derived consistently', async () => {
        const symbol = 'symbol';
        const decimals = 9;
        const prefix = arrayify('0xe95d1bd561a97aa5be610da1f641ee43729dd8c5aab1c7f8e90ea6d904901a50');

        const encoded = new Uint8Array(33 + symbol.length);

        encoded.set(prefix.reverse(), 0);
        encoded[32] = decimals;
        encoded.set(Buffer.from(symbol), 33);

        const txBuilder = new TxBuilder(client);

        await txBuilder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::token_id::unregistered_token_id`,
            arguments: [symbol, decimals],
        });
        const resp = await txBuilder.devInspect(keypair.toSuiAddress());
        const result = bcs.Address.parse(new Uint8Array(resp.results[0].returnValues[0][0]));

        expect(result).to.equal(keccak256(encoded));
    });

    it('should call register_transaction successfully', async () => {
        const txBuilder = new TxBuilder(client);

        await txBuilder.moveCall({
            target: `${deployments.example.packageId}::its::register_transaction`,
            arguments: [objectIds.relayerDiscovery, objectIds.singleton, objectIds.its, CLOCK_PACKAGE_ID],
        });

        const txResult = await txBuilder.signAndExecute(deployer);

        const discoveryTx = findObjectId(txResult, 'discovery::Transaction');
        expect(discoveryTx).to.be.not.null;
    });

    it('should register a coin successfully', async () => {
        const txBuilder = new TxBuilder(client);

        await txBuilder.moveCall({
            target: `${deployments.example.packageId}::its::register_coin`,
            arguments: [objectIds.its, objectIds.tokenCoinMetadata],
            typeArguments: [`${deployments.example.packageId}::token::TOKEN`],
        });

        const txResult = await txBuilder.signAndExecute(deployer, {
            showEvents: true,
        });

        objectIds.tokenId = txResult.events[0].parsedJson.token_id.id;

        expect(txResult.events.length).to.equal(1);
        expect(objectIds.tokenId).to.be.not.null;
    });

    describe('Two-way Calls', () => {
        before(async () => {
            await setupGateway();
            await registerItsTransaction();
            await setupTrustedAddresses(client, deployer, objectIds, deployments, [otherChain]);
        });

        describe('Interchain Token Transfer', () => {
            it('should send interchain transfer successfully', async () => {
                // Send interchain transfer
                const txBuilder = new TxBuilder(client);

                const tx = txBuilder.tx;

                const coin = tx.splitCoins(objectIds.token, [1e9]);
                const destinationAddress = '0x1234';
                const gas = tx.splitCoins(tx.gas, [1e8]);

                const TokenId = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::token_id::from_u256`,
                    arguments: [objectIds.tokenId],
                });

                await txBuilder.moveCall({
                    target: `${deployments.example.packageId}::its::send_interchain_transfer_call`,
                    arguments: [
                        objectIds.singleton,
                        objectIds.its,
                        objectIds.gateway,
                        objectIds.gasService,
                        TokenId,
                        coin,
                        otherChain,
                        destinationAddress,
                        '0x', // its token metadata
                        deployer.toSuiAddress(),
                        gas,
                        '0x', // gas params
                        CLOCK_PACKAGE_ID,
                    ],
                    typeArguments: [`${deployments.example.packageId}::token::TOKEN`],
                });

                await txBuilder.signAndExecute(deployer);
            });

            // This test depends on the previous one because it needs to have fund transferred to the coin_management contract beforehand.
            it('should receive interchain transfer successfully', async () => {
                // Approve ITS transfer message
                const messageType = ITSMessageType.InterchainTokenTransfer;
                const tokenId = objectIds.tokenId;
                const sourceAddress = '0x1234';
                const destinationAddress = objectIds.itsChannel; // The ITS Channel ID. All ITS messages are sent to this channel
                const amount = 1e9;
                const data = '0x1234';

                const discoveryInfo = {
                    packageId: deployments.relayer_discovery.packageId,
                    discovery: objectIds.relayerDiscovery,
                };
                // Channel ID for the ITS example. This will be encoded in the payload
                const itsExampleChannelId = await getSingletonChannelId(client, objectIds.singleton);

                // ITS transfer payload from Ethereum to Sui
                let payload = defaultAbiCoder.encode(
                    ['uint256', 'uint256', 'bytes', 'bytes', 'uint256', 'bytes'],
                    [messageType, tokenId, sourceAddress, itsExampleChannelId, amount, data],
                );
                payload = defaultAbiCoder.encode(['uint256', 'string', 'bytes'], [ITSMessageType.ReceiveFromItsHub, otherChain, payload]);

                const message = {
                    source_chain: trustedSourceChain,
                    message_id: hexlify(randomBytes(32)),
                    source_address: trustedSourceAddress,
                    destination_id: destinationAddress,
                    payload,
                    payload_hash: keccak256(payload),
                };
                await approveAndExecute(client, keypair, gatewayInfo, discoveryInfo, message);
            });
        });

        describe('Interchain Token Deployment', () => {
            it('should deploy remote interchain token to other chain successfully', async () => {
                const txBuilder = new TxBuilder(client);

                const tx = txBuilder.tx;
                const gas = tx.splitCoins(tx.gas, [1e8]);

                const TokenId = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::token_id::from_u256`,
                    arguments: [objectIds.tokenId],
                });

                await txBuilder.moveCall({
                    target: `${deployments.example.packageId}::its::deploy_remote_interchain_token`,
                    arguments: [
                        objectIds.its,
                        objectIds.gateway,
                        objectIds.gasService,
                        otherChain,
                        TokenId,
                        gas,
                        '0x',
                        deployer.toSuiAddress(),
                    ],
                    typeArguments: [`${deployments.example.packageId}::token::TOKEN`],
                });

                await txBuilder.signAndExecute(deployer);
            });

            it('should receive interchain token deployment from other chain successfully', async () => {
                // Define the interchain token options
                const interchainTokenOptions = {
                    symbol: 'IMD',
                    name: 'Interchain Moo Deng',
                    decimals: 6,
                };

                // Deploy the interchain token and store object ids for treasury cap and metadata
                const { packageId, publishTxn } = await publishInterchainToken(client, deployer, interchainTokenOptions);

                const symbol = interchainTokenOptions.symbol.toUpperCase();

                const typeArg = `${packageId}::${symbol.toLowerCase()}::${symbol}`;

                const treasuryCap = findObjectId(publishTxn, `TreasuryCap<${typeArg}>`);
                const metadata = findObjectId(publishTxn, `CoinMetadata<${typeArg}>`);

                const txBuilder = new TxBuilder(client);

                await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::give_unregistered_coin`,
                    arguments: [objectIds.its, treasuryCap, metadata],
                    typeArguments: [typeArg],
                });

                await txBuilder.signAndExecute(deployer);

                // Approve ITS transfer message
                const messageType = ITSMessageType.InterchainTokenDeployment;
                const tokenId = hexlify(randomBytes(32));
                const byteName = toUtf8Bytes(interchainTokenOptions.name);
                const byteSymbol = toUtf8Bytes(interchainTokenOptions.symbol);
                const decimals = interchainTokenOptions.decimals;
                const distributor = '0x';

                // ITS transfer payload from Ethereum to Sui
                let payload = defaultAbiCoder.encode(
                    ['uint256', 'uint256', 'bytes', 'bytes', 'uint256', 'bytes'],
                    [messageType, tokenId, byteName, byteSymbol, decimals, distributor],
                );
                payload = defaultAbiCoder.encode(['uint256', 'string', 'bytes'], [ITSMessageType.ReceiveFromItsHub, otherChain, payload]);

                const message = {
                    source_chain: trustedSourceChain,
                    message_id: hexlify(randomBytes(32)),
                    source_address: trustedSourceAddress,
                    destination_id: objectIds.itsChannel,
                    payload,
                    payload_hash: keccak256(payload),
                };

                await approveAndExecute(client, keypair, gatewayInfo, discoveryInfo, message);
            });
        });
    });
});
