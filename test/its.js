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
    SUI_PACKAGE_ID,
    STD_PACKAGE_ID,
    ITSTokenManagerType,
} = require('../dist/cjs');
const { keccak256, defaultAbiCoder, toUtf8Bytes, hexlify, randomBytes, arrayify } = require('ethers/lib/utils');
const { bcs } = require('@mysten/sui/bcs');
const { SUI_CLOCK_OBJECT_ID } = require('@mysten/sui/utils');

const PREFIX_SUI_CUSTOM_TOKEN_ID = '0xca5638c222d80aeaee69358fc5c11c4b3862bd9becdce249fcab9c679dbad782';

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

    async function createChannel() {
        const createChannelBuilder = new TxBuilder(client);

        const channel = await createChannelBuilder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::channel::new`,
            arguments: [],
        });

        await createChannelBuilder.moveCall({
            target: `${SUI_PACKAGE_ID}::transfer::public_transfer`,
            arguments: [channel, deployer.toSuiAddress()],
            typeArguments: [`${deployments.axelar_gateway.packageId}::channel::Channel`],
        });

        const receipt = await createChannelBuilder.signAndExecute(deployer);

        return findObjectId(receipt, `${deployments.axelar_gateway.packageId}::channel::Channel`);
    }

    async function registerCustomCoin(
        mintBurn,
        mintAmount = 0,
        tokenOptions = {
            symbol: 'CT',
            name: 'Custom Token',
            decimals: 6,
        },
    ) {
        // Deploy the interchain token and store object ids for treasury cap and metadata
        const { packageId, publishTxn } = await publishInterchainToken(client, deployer, tokenOptions);

        const symbol = tokenOptions.symbol.toUpperCase();

        const coinType = `${packageId}::${symbol.toLowerCase()}::${symbol}`;

        const treasuryCap = findObjectId(publishTxn, `TreasuryCap<${coinType}>`);
        const coinMetadata = findObjectId(publishTxn, `CoinMetadata<${coinType}>`);

        const channel = await createChannel();
        const salt = getRandomBytes32();

        const txBuilder = new TxBuilder(client);

        if (mintAmount > 0) {
            await txBuilder.moveCall({
                target: `${SUI_PACKAGE_ID}::coin::mint_and_transfer`,
                arguments: [treasuryCap, mintAmount, deployer.toSuiAddress()],
                typeArguments: [coinType],
            });
        }

        let coinManagement;

        if (mintBurn) {
            coinManagement = await txBuilder.moveCall({
                target: `${deployments.interchain_token_service.packageId}::coin_management::new_with_cap`,
                arguments: [treasuryCap],
                typeArguments: [coinType],
            });
        } else {
            coinManagement = await txBuilder.moveCall({
                target: `${deployments.interchain_token_service.packageId}::coin_management::new_locked`,
                arguments: [],
                typeArguments: [coinType],
            });
        }

        const saltObject = await txBuilder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::bytes32::new`,
            arguments: [salt],
        });

        const [, reclaimerOption] = await txBuilder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::interchain_token_service::register_custom_coin`,
            arguments: [objectIds.its, channel, saltObject, coinMetadata, coinManagement],
            typeArguments: [coinType],
        });

        if (mintBurn) {
            const treasutyCapReclaimer = await txBuilder.moveCall({
                target: `${STD_PACKAGE_ID}::option::destroy_some`,
                arguments: [reclaimerOption],
                typeArguments: [
                    `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
                ],
            });

            await txBuilder.moveCall({
                target: `${SUI_PACKAGE_ID}::transfer::public_transfer`,
                arguments: [treasutyCapReclaimer, deployer.toSuiAddress()],
                typeArguments: [
                    `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
                ],
            });
        } else {
            await txBuilder.moveCall({
                target: `${STD_PACKAGE_ID}::option::destroy_none`,
                arguments: [reclaimerOption],
                typeArguments: [
                    `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
                ],
            });
        }

        const receipt = await txBuilder.signAndExecute(deployer);
        let coinObject, treasuryCapReclaimer;

        if (mintAmount > 0) {
            coinObject = await findObjectId(receipt, `${SUI_PACKAGE_ID}::coin::Coin<${coinType}>`);
        }

        if (mintBurn) {
            treasuryCapReclaimer = await findObjectId(
                receipt,
                `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
            );
        }

        const customTokenId = bcs.struct('CustomTokenId', {
            prefix: bcs.Address,
            chain_name_hash: bcs.Address,
            deployer: bcs.Address,
            salt: bcs.Address,
        });

        const tokenIdData = customTokenId
            .serialize({
                prefix: PREFIX_SUI_CUSTOM_TOKEN_ID,
                chain_name_hash: keccak256('0x' + Buffer.from(chainName, 'utf8').toString('hex')),
                deployer: channel,
                salt,
            })
            .toBytes();

        const tokenId = keccak256(hexlify(tokenIdData));

        return { coinType, tokenId, coinObject, channel, treasuryCapReclaimer };
    }

    async function giveUnlinkedCoin(
        mintBurn,
        mintAmount = 0,
        tokenOptions = {
            symbol: 'UC',
            name: 'Unlinked Coin',
            decimals: 6,
        },
    ) {
        // Deploy the interchain token and store object ids for treasury cap and metadata
        const { packageId, publishTxn } = await publishInterchainToken(client, deployer, tokenOptions);

        const symbol = tokenOptions.symbol.toUpperCase();

        const coinType = `${packageId}::${symbol.toLowerCase()}::${symbol}`;

        const treasuryCap = findObjectId(publishTxn, `TreasuryCap<${coinType}>`);
        const coinMetadata = findObjectId(publishTxn, `CoinMetadata<${coinType}>`);

        const channel = await createChannel();
        const tokenId = getRandomBytes32();

        const txBuilder = new TxBuilder(client);

        if (mintAmount > 0) {
            await txBuilder.moveCall({
                target: `${SUI_PACKAGE_ID}::coin::mint_and_transfer`,
                arguments: [treasuryCap, mintAmount, deployer.toSuiAddress()],
                typeArguments: [coinType],
            });
        }

        let treasuryCapOption;

        if (mintBurn) {
            treasuryCapOption = await txBuilder.moveCall({
                target: `${STD_PACKAGE_ID}::option::some`,
                arguments: [treasuryCap],
                typeArguments: [`${SUI_PACKAGE_ID}::coin::TreasuryCap<${coinType}>`],
            });
        } else {
            treasuryCapOption = await txBuilder.moveCall({
                target: `${STD_PACKAGE_ID}::option::none`,
                arguments: [],
                typeArguments: [`${SUI_PACKAGE_ID}::coin::TreasuryCap<${coinType}>`],
            });
        }

        const tokenIdObject = await txBuilder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::token_id::from_address`,
            arguments: [tokenId],
        });

        const reclaimerOption = await txBuilder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::interchain_token_service::give_unlinked_coin`,
            arguments: [objectIds.its, tokenIdObject, coinMetadata, treasuryCapOption],
            typeArguments: [coinType],
        });

        if (mintBurn) {
            const treasutyCapReclaimer = await txBuilder.moveCall({
                target: `${STD_PACKAGE_ID}::option::destroy_some`,
                arguments: [reclaimerOption],
                typeArguments: [
                    `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
                ],
            });

            await txBuilder.moveCall({
                target: `${SUI_PACKAGE_ID}::transfer::public_transfer`,
                arguments: [treasutyCapReclaimer, deployer.toSuiAddress()],
                typeArguments: [
                    `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
                ],
            });
        } else {
            await txBuilder.moveCall({
                target: `${STD_PACKAGE_ID}::option::destroy_none`,
                arguments: [reclaimerOption],
                typeArguments: [
                    `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
                ],
            });
        }

        const receipt = await txBuilder.signAndExecute(deployer);
        let coinObject, treasuryCapReclaimer;

        if (mintAmount > 0) {
            coinObject = await findObjectId(receipt, `${SUI_PACKAGE_ID}::coin::Coin<${coinType}>`);
        }

        if (mintBurn) {
            treasuryCapReclaimer = await findObjectId(
                receipt,
                `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
            );
        }

        return { coinType, tokenId, coinObject, channel, treasuryCapReclaimer };
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

        describe('Custom Token Deployment', () => {
            it('should register a custom lock/unlock token successfully', async () => {
                const { coinType, tokenId } = await registerCustomCoin(false);

                const queryTypeBuilder = new TxBuilder(client);

                const tokenIdObject = await queryTypeBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::token_id::from_address`,
                    arguments: [tokenId],
                });
                await queryTypeBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::registered_coin_type`,
                    arguments: [objectIds.its, tokenIdObject],
                });

                const registeredCoinType =
                    '0x' +
                    bcs.String.parse(
                        new Uint8Array((await queryTypeBuilder.devInspect(deployer.toSuiAddress())).results[1].returnValues[0][0]),
                    );

                expect(registeredCoinType).to.equal(coinType);
            });

            it('should register a custom mint/burn token successfully', async () => {
                const { coinType, tokenId } = await registerCustomCoin(true);

                const queryTypeBuilder = new TxBuilder(client);

                const tokenIdObject = await queryTypeBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::token_id::from_address`,
                    arguments: [tokenId],
                });
                await queryTypeBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::registered_coin_type`,
                    arguments: [objectIds.its, tokenIdObject],
                });

                const registeredCoinType =
                    '0x' +
                    bcs.String.parse(
                        new Uint8Array((await queryTypeBuilder.devInspect(deployer.toSuiAddress())).results[1].returnValues[0][0]),
                    );

                expect(registeredCoinType).to.equal(coinType);
            });

            it('should register a send a mint/burn coin', async () => {
                const destinationAddress = '0x1234';
                const metadata = '0x';
                const { coinType, tokenId, coinObject, channel } = await registerCustomCoin(true, 10);

                const txBuilder = new TxBuilder(client);

                const tokenIdObject = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::token_id::from_address`,
                    arguments: [tokenId],
                });

                const interchainTransferTicket = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::prepare_interchain_transfer`,
                    arguments: [tokenIdObject, coinObject, otherChain, destinationAddress, metadata, channel],
                    typeArguments: [coinType],
                });

                const messageTicket = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::send_interchain_transfer`,
                    arguments: [objectIds.its, interchainTransferTicket, SUI_CLOCK_OBJECT_ID],
                    typeArguments: [coinType],
                });

                await txBuilder.moveCall({
                    target: `${deployments.axelar_gateway.packageId}::gateway::send_message`,
                    arguments: [objectIds.gateway, messageTicket],
                });

                await txBuilder.signAndExecute(deployer);
            });

            it('should register a custom mint/burn token and reclaim the TreasuryCap', async () => {
                const { coinType, tokenId, treasuryCapReclaimer } = await registerCustomCoin(true);
                const txBuilder = new TxBuilder(client);

                const tokenIdObject = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::token_id::from_address`,
                    arguments: [tokenId],
                });

                const treasuryCap = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::remove_treasury_cap`,
                    arguments: [objectIds.its, treasuryCapReclaimer],
                    typeArguments: [coinType],
                });

                const restoredTreasuryCapReclaimer = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::restore_treasury_cap`,
                    arguments: [objectIds.its, treasuryCap, tokenIdObject],
                    typeArguments: [coinType],
                });

                await txBuilder.moveCall({
                    target: `${SUI_PACKAGE_ID}::transfer::public_transfer`,
                    arguments: [restoredTreasuryCapReclaimer, deployer.toSuiAddress()],
                    typeArguments: [
                        `${deployments.interchain_token_service.packageId}::treasury_cap_reclaimer::TreasuryCapReclaimer<${coinType}>`,
                    ],
                });

                await txBuilder.signAndExecute(deployer);
            });
        });

        describe('Custom Token Reception', () => {
            it('should register a mint/burn coin remotely', async () => {
                const { tokenId, coinType } = await giveUnlinkedCoin(true);

                // Approve ITS transfer message
                const messageType = ITSMessageType.LinkToken;
                const tokenManagerType = ITSTokenManagerType.MintBurn;
                const sourceTokenAddress = '0x1234';
                const linkParams = '0x';

                // ITS transfer payload from Ethereum to Sui
                let payload = defaultAbiCoder.encode(
                    ['uint256', 'uint256', 'uint256', 'bytes', 'string', 'bytes'],
                    [messageType, tokenId, tokenManagerType, sourceTokenAddress, coinType.slice(2), linkParams],
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

                const queryTypeBuilder = new TxBuilder(client);

                const tokenIdObject = await queryTypeBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::token_id::from_address`,
                    arguments: [tokenId],
                });
                await queryTypeBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::registered_coin_type`,
                    arguments: [objectIds.its, tokenIdObject],
                });

                const registeredCoinType =
                    '0x' +
                    bcs.String.parse(
                        new Uint8Array((await queryTypeBuilder.devInspect(deployer.toSuiAddress())).results[1].returnValues[0][0]),
                    );

                expect(registeredCoinType).to.equal(coinType);
            });

            it('should remove an unlinked coin treasury cap', async () => {
                const { coinType, treasuryCapReclaimer } = await giveUnlinkedCoin(true);

                const txBuilder = new TxBuilder(client);

                const treasuryCap = await txBuilder.moveCall({
                    target: `${deployments.interchain_token_service.packageId}::interchain_token_service::remove_unlinked_coin`,
                    arguments: [objectIds.its, treasuryCapReclaimer],
                    typeArguments: [coinType],
                });

                await txBuilder.moveCall({
                    target: `${SUI_PACKAGE_ID}::transfer::public_transfer`,
                    arguments: [treasuryCap, deployer.toSuiAddress()],
                    typeArguments: [`${SUI_PACKAGE_ID}::coin::TreasuryCap<${coinType}>`],
                });

                await txBuilder.signAndExecute(deployer);
            });
        });
    });
});
