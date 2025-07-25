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
const { bcs } = require('@mysten/sui/bcs');
const {
    publishPackage,
    generateEd25519Keypairs,
    findObjectId,
    getRandomBytes32,
    calculateNextSigners,
    getVersionedChannelId,
    setupTrustedAddresses,
    approveAndExecuteMessage,
    publishExternalPackage,
} = require('./testutils');
const { CLOCK_PACKAGE_ID, getDeploymentOrder, fundAccountsFromFaucet, bcsStructs, ITSMessageType, TxBuilder } = require('../dist/cjs');
const { keccak256, defaultAbiCoder, hexlify, randomBytes } = require('ethers/lib/utils');
const chai = require('chai');
const { expect } = chai;

const SUI = '0x2';

describe('Squid', () => {
    // Sui Client
    let client;
    const network = process.env.NETWORK || 'localnet';

    // Store the deployed packages info
    const deployments = {};

    // Store the object ids from move transactions
    let objectIds = {};

    // A list of contracts to publish
    const dependencies = getDeploymentOrder('squid', `${__dirname}/../move`);
    // should be ['version_control', 'utils', 'axelar_gateway', 'gas_service', 'abi', 'governance', 'relayer_discovery', 'its', 'example']

    // Parameters for Gateway Setup
    const gatewayInfo = {};
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

    const coins = {};
    const pools = {};

    // Initializes the gateway object.
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
        gatewayInfo.discoveryPackageId;
        gatewayInfo.discoveryPackageId = deployments.relayer_discovery.packageId;
        gatewayInfo.discovery = objectIds.relayerDiscovery;
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

    // Registers the ITS in relayer discovery
    async function registerItsTransaction() {
        const registerTransactionBuilder = new TxBuilder(client);

        await registerTransactionBuilder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::discovery::register_transaction`,
            arguments: [objectIds.its, objectIds.relayerDiscovery],
        });

        await registerTransactionBuilder.signAndExecute(deployer);
    }

    // Registers Squid in relyaer discovery
    async function registerSquidTransaction() {
        const registerTransactionBuilder = new TxBuilder(client);

        await registerTransactionBuilder.moveCall({
            target: `${deployments.squid.packageId}::discovery::register_transaction`,
            arguments: [objectIds.squid, objectIds.its, objectIds.gateway, objectIds.relayerDiscovery],
        });

        await registerTransactionBuilder.signAndExecute(deployer);
    }

    // Deploys the deepbook package (and the DEEP token).
    async function deployDeepbook() {
        deployments.token = await publishExternalPackage(client, deployer, 'token', `${__dirname}/../node_modules/deepbookv3/packages`);
        deployments.deepbook = await publishExternalPackage(
            client,
            deployer,
            'deepbook',
            `${__dirname}/../node_modules/deepbookv3/packages`,
        );
    }

    // Funds sui with some DEEP
    async function giveDeepToSquid() {
        const giveDeepBuilder = new TxBuilder(client);

        await giveDeepBuilder.moveCall({
            target: `${deployments.squid.packageId}::squid::give_deep`,
            arguments: [objectIds.squid, objectIds.deepCoin],
        });

        await giveDeepBuilder.signAndExecute(deployer);
    }

    // Creates a balance manager (used to fund deepbook pools)
    async function createBalanceManager(keypair = deployer) {
        const builder = new TxBuilder(client);

        const balanceManager = await builder.moveCall({
            target: `${deployments.deepbook.packageId}::balance_manager::new`,
            arguments: [],
            typeArguments: [],
        });

        builder.tx.transferObjects([balanceManager], keypair.toSuiAddress());
        const executeTxn = await builder.signAndExecute(deployer);
        return findObjectId(executeTxn, `BalanceManager`);
    }

    // Creates a deepbook pool
    async function createPool(coin1, coin2, tickSize = 100, lotSize = 100, minSize = 100, whitelistedPool = true, stablePool = false) {
        const builder = new TxBuilder(client);

        await builder.moveCall({
            target: `${deployments.deepbook.packageId}::pool::create_pool_admin`,
            arguments: [objectIds.deepbookRegistry, tickSize, lotSize, minSize, whitelistedPool, stablePool, objectIds.deepbookAdminCap],
            typeArguments: [coins[coin1].type, coins[coin2].type],
        });
        const executeTxn = await builder.signAndExecute(deployer);

        return findObjectId(executeTxn, `pool::Pool`, 'created', 'PoolInner');
    }

    // Funds a deepbook pool
    async function fundPool(coin1, coin2, amount, price = 1000000000) {
        const builder = new TxBuilder(client);
        const tradeProof = await builder.moveCall({
            target: `${deployments.deepbook.packageId}::balance_manager::generate_proof_as_owner`,
            arguments: [objectIds.balanceManager],
            typeArguments: [],
        });
        const input = await builder.moveCall({
            target: `${SUI}::coin::mint`,
            arguments: [coins[coin2].treasuryCap, amount],
            typeArguments: [coins[coin2].type],
        });
        await builder.moveCall({
            target: `${deployments.deepbook.packageId}::balance_manager::deposit`,
            arguments: [objectIds.balanceManager, input],
            typeArguments: [coins[coin2].type],
        });
        await builder.moveCall({
            target: `${deployments.deepbook.packageId}::pool::place_limit_order`,
            arguments: [
                pools[coin1 + coin2],
                objectIds.balanceManager,
                tradeProof,
                0,
                0,
                0,
                price,
                amount,
                true,
                true,
                1000000000000000,
                CLOCK_PACKAGE_ID,
            ],
            typeArguments: [coins[coin1].type, coins[coin2].type],
        });

        await builder.signAndExecute(deployer);
    }

    // Funds an ITS lock/unlock token by sending a call.
    async function fundIts(amount, coinName = 'a') {
        const builder = new TxBuilder(client);

        const input = await builder.moveCall({
            target: `${SUI}::coin::mint`,
            arguments: [coins[coinName].treasuryCap, amount],
            typeArguments: [coins[coinName].type],
        });

        const channel = await builder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::channel::new`,
            arguments: [],
            typeArguments: [],
        });

        const tokenId = await builder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::token_id::from_address`,
            arguments: [objectIds.tokenId],
            typeArguments: [],
        });

        const interchainTransfer = await builder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::interchain_token_service::prepare_interchain_transfer`,
            arguments: [tokenId, input, otherChain, '0xadd1', '0x', channel],
            typeArguments: [coins[coinName].type],
        });

        const messageTicket = await builder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::interchain_token_service::send_interchain_transfer`,
            arguments: [objectIds.its, interchainTransfer, CLOCK_PACKAGE_ID],
            typeArguments: [coins[coinName].type],
        });

        await builder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::gateway::send_message`,
            arguments: [objectIds.gateway, messageTicket],
            typeArguments: [],
        });

        await builder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::channel::destroy`,
            arguments: [channel],
            typeArguments: [],
        });
        await builder.signAndExecute(deployer);
    }

    // Registers a coin with ITS
    async function registerCoin(coin) {
        const builder = new TxBuilder(client);

        const coinManagment = await builder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::coin_management::new_locked`,
            arguments: [],
            typeArguments: [coins[coin].type],
        });
        await builder.moveCall({
            target: `${deployments.interchain_token_service.packageId}::interchain_token_service::register_coin_from_metadata`,
            arguments: [objectIds.its, coins[coin].coinMetadata, coinManagment],
            typeArguments: [coins[coin].type],
        });

        const registerTxn = await builder.signAndExecute(deployer, { showEvents: true });

        objectIds.tokenId = registerTxn.events[0].parsedJson.token_id.id;
    }

    // Get the swap data for the Squid transaction. We have these be consistent but test different scenarios.
    function getSwapData() {
        const swap1 = bcsStructs.squid.DeepbookV3SwapData.serialize({
            swap_type: { DeepbookV3: null },
            pool_id: pools.ab,
            has_base: true,
            min_output: 1,
            base_type: coins.a.type.slice(2),
            quote_type: coins.b.type.slice(2),
            lot_size: 100,
            should_sweep: true,
        }).toBytes();

        const swap2 = bcsStructs.squid.DeepbookV3SwapData.serialize({
            swap_type: { DeepbookV3: null },
            pool_id: pools.bc,
            has_base: true,
            min_output: 1,
            base_type: coins.b.type.slice(2),
            quote_type: coins.c.type.slice(2),
            lot_size: 100,
            should_sweep: true,
        }).toBytes();

        const transfer = bcsStructs.squid.SuiTransferSwapData.serialize({
            swap_type: { SuiTransfer: null },
            coin_type: coins.c.type.slice(2),
            recipient: keypair.toSuiAddress(),
            fallback: false,
        }).toBytes();

        const fallback = bcsStructs.squid.SuiTransferSwapData.serialize({
            swap_type: { SuiTransfer: null },
            coin_type: coins.a.type.slice(2),
            recipient: keypair.toSuiAddress(),
            fallback: true,
        }).toBytes();

        const swapData = bcs.vector(bcs.vector(bcs.U8)).serialize([swap1, swap2, transfer, fallback]).toBytes();
        return swapData;
    }

    // Query all the coins that `keypair` has, and then give them away so that future queries are informative still.
    async function getAndLoseCoins() {
        // wait a bit since coins sometimes take a bit to load.
        await new Promise((resolve) => setTimeout(resolve, 1000));
        const ownedCoins = await client.getAllCoins({
            owner: keypair.toSuiAddress(),
        });
        const balances = {};
        const builder = new TxBuilder(client);

        for (const coinName of ['a', 'b', 'c']) {
            const coin = ownedCoins.data.find((coin) => coin.coinType === coins[coinName].type);

            if (!coin) {
                balances[coinName] = 0;
                continue;
            }

            balances[coinName] = Number(coin.balance);

            builder.tx.transferObjects([coin.coinObjectId], deployer.toSuiAddress());
        }

        await builder.signAndExecute(keypair);
        return balances;
    }

    before(async () => {
        client = new SuiClient({ url: getFullnodeUrl(network) });

        // Request funds from faucet
        const addresses = [operator, deployer, keypair].map((keypair) => keypair.toSuiAddress());
        await fundAccountsFromFaucet(addresses);

        await deployDeepbook();

        objectIds = {
            balanceManager: await createBalanceManager(),
            deepCoin: findObjectId(deployments.token.publishTxn, `Coin<${deployments.token.packageId}`),
            deepbookAdminCap: findObjectId(deployments.deepbook.publishTxn, 'DeepbookAdminCap'),
            deepbookRegistry: findObjectId(deployments.deepbook.publishTxn, 'Registry', 'created', 'RegistryInner'),
        };

        dependencies.push('gas_service', 'example');

        // Publish all packages
        for (const packageDir of dependencies) {
            let publishedReceipt;

            if (packageDir === 'squid') {
                publishedReceipt = await publishPackage(client, deployer, packageDir, { showEvents: true }, (moveJson) => {
                    moveJson.dependencies.deepbook = { local: '../deepbook' };
                    moveJson.dependencies.token = { local: '../token' };
                    return moveJson;
                });
            } else {
                publishedReceipt = await publishPackage(client, deployer, packageDir, { showEvents: true });
            }

            deployments[packageDir] = publishedReceipt;
        }

        objectIds = {
            ...objectIds,
            squid: findObjectId(deployments.squid.publishTxn, 'squid::Squid'),
            squidV0: findObjectId(deployments.squid.publishTxn, 'squid_v0::Squid_v0'),
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
            gateway: findObjectId(
                deployments.interchain_token_service.publishTxn,
                `${deployments.axelar_gateway.packageId}::gateway::Gateway`,
            ),
        };

        await setupIts();

        // Find the object ids from the publish transactions
        objectIds = {
            ...objectIds,
            itsChannel: await getVersionedChannelId(client, objectIds.itsV0),
            squidChannel: await getVersionedChannelId(client, objectIds.squidV0),
        };

        for (const token of ['a', 'b', 'c']) {
            const name = `token_${token}`;
            const type = `${deployments.example.packageId}::${name}::${name.toUpperCase()}`;
            coins[token] = {
                treasuryCap: findObjectId(deployments.example.publishTxn, `TreasuryCap<${type}>`),
                coinMetadata: findObjectId(deployments.example.publishTxn, `CoinMetadata<${type}>`),
                type,
            };
        }

        pools.ab = await createPool('a', 'b');
        pools.bc = await createPool('b', 'c');
        await setupGateway();
        await registerItsTransaction();
        await registerSquidTransaction();
        await setupTrustedAddresses(client, deployer, objectIds, deployments, [otherChain]);
        await registerCoin('a');
        await giveDeepToSquid();
    });

    it('should succesfully perform a swap', async () => {
        const swapData = getSwapData();
        const amount = 1e6;

        await fundIts(amount);
        await fundPool('a', 'b', amount);
        await fundPool('b', 'c', amount);

        const messageType = ITSMessageType.InterchainTokenTransfer;
        const tokenId = objectIds.tokenId;
        const sourceAddress = '0x1234';
        const destinationAddress = objectIds.itsChannel; // The ITS Channel ID. All ITS messages are sent to this channel
        const data = swapData;
        // Channel ID for Squid. This will be encoded in the payload
        const squidChannelId = objectIds.squidChannel;
        // ITS transfer payload from Ethereum to Sui
        let payload = defaultAbiCoder.encode(
            ['uint256', 'uint256', 'bytes', 'bytes', 'uint256', 'bytes'],
            [messageType, tokenId, sourceAddress, squidChannelId, amount, data],
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

        await approveAndExecuteMessage(client, keypair, gatewayInfo, message);

        const balances = await getAndLoseCoins();
        expect(balances.a).to.equal(0);
        expect(balances.b).to.equal(0);
        expect(balances.c).to.equal(amount);
    });

    it('should succesfully fallback whn pools are not funded properly', async () => {
        const swapData = getSwapData();
        const amount = 1e6;

        await fundIts(amount);

        const messageType = ITSMessageType.InterchainTokenTransfer;
        const tokenId = objectIds.tokenId;
        const sourceAddress = '0x1234';
        const destinationAddress = objectIds.itsChannel; // The ITS Channel ID. All ITS messages are sent to this channel
        const data = swapData;
        // Channel ID for Squid. This will be encoded in the payload
        const squidChannelId = objectIds.squidChannel;
        // ITS transfer payload from Ethereum to Sui
        let payload = defaultAbiCoder.encode(
            ['uint256', 'uint256', 'bytes', 'bytes', 'uint256', 'bytes'],
            [messageType, tokenId, sourceAddress, squidChannelId, amount, data],
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

        await approveAndExecuteMessage(client, keypair, gatewayInfo, message);

        const balances = await getAndLoseCoins();
        expect(balances.a).to.equal(amount);
        expect(balances.b).to.equal(0);
        expect(balances.c).to.equal(0);
    });
});
