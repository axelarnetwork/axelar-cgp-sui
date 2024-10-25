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
const { CLOCK_PACKAGE_ID } = require('../dist/types');
const { getDeploymentOrder, fundAccountsFromFaucet } = require('../dist/utils');
const { bcsStructs } = require('../dist/bcs');
const { ITSMessageType } = require('../dist/types');
const { TxBuilder } = require('../dist/tx-builder');
const { keccak256, defaultAbiCoder, hexlify, randomBytes } = require('ethers/lib/utils');

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
    const trustedSourceChain = 'Avalanche';
    const trustedSourceAddress = hexlify(randomBytes(20));
    const coins = {};
    const pools = {};

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

    async function registerItsTransaction() {
        const registerTransactionBuilder = new TxBuilder(client);

        await registerTransactionBuilder.moveCall({
            target: `${deployments.its.packageId}::discovery::register_transaction`,
            arguments: [objectIds.its, objectIds.relayerDiscovery],
        });

        await registerTransactionBuilder.signAndExecute(deployer);
    }

    async function registerSquidTransaction() {
        const registerTransactionBuilder = new TxBuilder(client);

        await registerTransactionBuilder.moveCall({
            target: `${deployments.squid.packageId}::discovery::register_transaction`,
            arguments: [objectIds.squid, objectIds.its, objectIds.gateway, objectIds.relayerDiscovery],
        });

        await registerTransactionBuilder.signAndExecute(deployer);
    }

    async function deployDeepbook() {
        deployments.token = await publishExternalPackage(client, deployer, 'token', `${__dirname}/../node_modules/deepbookv3/packages`);
        deployments.deepbook = await publishExternalPackage(
            client,
            deployer,
            'deepbook',
            `${__dirname}/../node_modules/deepbookv3/packages`,
        );
    }

    async function giveDeepToSquid() {
        const giveDeepBuilder = new TxBuilder(client);

        await giveDeepBuilder.moveCall({
            target: `${deployments.squid.packageId}::squid::give_deep`,
            arguments: [objectIds.squid, objectIds.deepCoin],
        });

        await giveDeepBuilder.signAndExecute(deployer);
    }

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

    async function fundPool(coin1, coin2, amount, price = 10000000) {
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

    async function registerCoin(coin) {
        const builder = new TxBuilder(client);

        const coinInfo = await builder.moveCall({
            target: `${deployments.its.packageId}::coin_info::from_metadata`,
            arguments: [coins[coin].coinMetadata, 9],
            typeArguments: [coins[coin].type],
        });
        const coinManagment = await builder.moveCall({
            target: `${deployments.its.packageId}::coin_management::new_with_cap`,
            arguments: [coins[coin].treasuryCap],
            typeArguments: [coins[coin].type],
        });
        await builder.moveCall({
            target: `${deployments.its.packageId}::its::register_coin`,
            arguments: [objectIds.its, coinInfo, coinManagment],
            typeArguments: [coins[coin].type],
        });

        const registerTxn = await builder.signAndExecute(deployer, { showEvents: true });

        objectIds.tokenId = registerTxn.events[0].parsedJson.token_id.id;
    }

    before(async () => {
        client = new SuiClient({ url: getFullnodeUrl(network) });

        // Request funds from faucet
        const addresses = [operator, deployer, keypair].map((keypair) => keypair.toSuiAddress());
        await fundAccountsFromFaucet(addresses);

        await deployDeepbook();

        objectIds = {
            balanceManager: await createBalanceManager(),
            deepCoin: findObjectId(deployments.token.publishTxn, 'Coin'),
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
            its: findObjectId(deployments.its.publishTxn, 'its::ITS'),
            itsV0: findObjectId(deployments.its.publishTxn, 'its_v0::ITS_v0'),
            relayerDiscovery: findObjectId(
                deployments.relayer_discovery.publishTxn,
                `${deployments.relayer_discovery.packageId}::discovery::RelayerDiscovery`,
            ),
            gasService: findObjectId(deployments.gas_service.publishTxn, `${deployments.gas_service.packageId}::gas_service::GasService`),
            creatorCap: findObjectId(deployments.axelar_gateway.publishTxn, 'CreatorCap'),
            itsOwnerCap: findObjectId(deployments.its.publishTxn, `${deployments.its.packageId}::owner_cap::OwnerCap`),
        };
        // Find the object ids from the publish transactions
        objectIds = {
            ...objectIds,
            itsChannel: await getVersionedChannelId(client, objectIds.itsV0),
            squidChannel: await getVersionedChannelId(client, objectIds.squidV0),
        };
        for(token of ['a', 'b', 'c']) {  
            const type = `${deployments.example.packageId}::${token}::${token.toUpperCase()}`;
            coins[token] = {
                treasuryCap: findObjectId(deployments.example.publishTxn, `TreasuryCap<${type}>`),
                coinMetadata: findObjectId(deployments.example.publishTxn, `CoinMetadata<${type}>`),
                type,
            };
        }

        pools.ab = await createPool('a', 'b');
        pools.bc = await createPool('b', 'c');
        await fundPool('a', 'b', 1000000);

        await setupGateway();
        await registerItsTransaction();
        await registerSquidTransaction();
        await setupTrustedAddresses(client, deployer, objectIds, deployments, [trustedSourceAddress], [trustedSourceChain]);
        await registerCoin('a');
        await giveDeepToSquid();
    });

    it('should call register_transaction successfully', async () => {
        console.log(
            await client.getAllCoins({
                owner: keypair.toSuiAddress(),
            }),
        );
        const swap = bcsStructs.squid.DeepbookV3SwapData.serialize({
            swap_type: { DeepbookV3: null },
            pool_id: pools.ab,
            has_base: true,
            min_output: 1,
            base_type: coins.a.type.slice(2),
            quote_type: coins.b.type.slice(2),
            lot_size: 100,
            should_sweep: true,
        }).toBytes();
        const transfer = bcsStructs.squid.SuiTransferSwapData.serialize({
            swap_type: { SuiTransfer: null },
            coin_type: coins.b.type.slice(2),
            recipient: keypair.toSuiAddress(),
            fallback: false,
        }).toBytes();
        const fallback = bcsStructs.squid.SuiTransferSwapData.serialize({
            swap_type: { SuiTransfer: null },
            coin_type: coins.a.type.slice(2),
            recipient: keypair.toSuiAddress(),
            fallback: true,
        }).toBytes();
        console.log(swap, transfer);
        const swapData = bcs.vector(bcs.vector(bcs.U8)).serialize([swap, transfer, fallback]).toBytes();

        const messageType = ITSMessageType.InterchainTokenTransfer;
        const tokenId = objectIds.tokenId;
        const sourceAddress = trustedSourceAddress;
        const destinationAddress = objectIds.itsChannel; // The ITS Channel ID. All ITS messages are sent to this channel
        const amount = 1e6;
        const data = swapData;
        // Channel ID for Squid. This will be encoded in the payload
        const squidChannelId = objectIds.squidChannel;
        // ITS transfer payload from Ethereum to Sui
        const payload = defaultAbiCoder.encode(
            ['uint256', 'uint256', 'bytes', 'bytes', 'uint256', 'bytes'],
            [messageType, tokenId, sourceAddress, squidChannelId, amount, data],
        );

        const message = {
            source_chain: trustedSourceChain,
            message_id: hexlify(randomBytes(32)),
            source_address: trustedSourceAddress,
            destination_id: destinationAddress,
            payload,
            payload_hash: keccak256(payload),
        };

        await approveAndExecuteMessage(client, keypair, gatewayInfo, message);

        console.log(
            await client.getAllCoins({
                owner: keypair.toSuiAddress(),
            }),
        );
    });
});
