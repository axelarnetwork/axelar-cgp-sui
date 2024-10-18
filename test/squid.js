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
const {
    publishPackage,
    publishInterchainToken,
    generateEd25519Keypairs,
    findObjectId,
    getRandomBytes32,
    calculateNextSigners,
    getSingletonChannelId,
    getITSChannelId,
    setupTrustedAddresses,
    approveAndExecuteMessage,
    publishExternalPackage,
} = require('./testutils');
const { expect } = require('chai');
const { CLOCK_PACKAGE_ID } = require('../dist/types');
const { getDeploymentOrder, fundAccountsFromFaucet, updateMoveToml } = require('../dist/utils');
const { bcsStructs } = require('../dist/bcs');
const { ITSMessageType } = require('../dist/types');
const { TxBuilder } = require('../dist/tx-builder');
const { keccak256, defaultAbiCoder, toUtf8Bytes, hexlify, randomBytes } = require('ethers/lib/utils');

const SUI = '0x2';
const STD = '0x1'

describe.only('Squid', () => {
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

    async function deployDeepbook() {
        deployments.token = await publishExternalPackage(client, deployer, 'token', `${__dirname}/../node_modules/deepbookv3/packages`);
        deployments.deepbook = await publishExternalPackage(client, deployer, 'deepbook', `${__dirname}/../node_modules/deepbookv3/packages`);
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

    async function createPool(coin1, coin2, tickSize = 100, lotSize = 100, minSize = 100, whitelistedPool = false, stablePool = false) {
        const builder = new TxBuilder(client);

        await builder.moveCall({
            target: `${deployments.deepbook.packageId}::pool::create_pool_admin`,
            arguments: [
                objectIds.deepbookRegistry,
                tickSize,
                lotSize,
                minSize,
                whitelistedPool,
                stablePool,
                objectIds.deepbookAdminCap,
            ],
            typeArguments: [coins[coin1].type, coins[coin2].type],
        });
        const executeTxn = await builder.signAndExecute(deployer);
        return findObjectId(executeTxn, `Pool`);
    }

    async function fundPool(coin1, coin2, amount, price = 10000000) {
        const builder = new TxBuilder(client);
        const tradeProof = await builder.moveCall({
            target: `${deployments.deepbook.packageId}::balance_manager::generate_proof_as_owner`,
            arguments: [
                objectIds.balanceManager,
            ],
            typeArguments: [],
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
                
            ],
            typeArguments: [coins[coin1].type, coins[coin2].type],
        });
        /*place_limit_order<BaseAsset, QuoteAsset>(
            self: &mut Pool<BaseAsset, QuoteAsset>,
            balance_manager: &mut BalanceManager,
            trade_proof: &TradeProof,
            client_order_id: u64,
            order_type: u8,
            self_matching_option: u8,
            price: u64,
            quantity: u64,
            is_bid: bool,
            pay_with_deep: bool,
            expire_timestamp: u64,
            clock: &Clock,
            ctx: &TxContext,
        )*/
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
        }

        dependencies.push('gas_service', 'example');
        // Publish all packages
        for (const packageDir of dependencies) {console.log(packageDir);
            const publishedReceipt = await publishPackage(client, deployer, packageDir);

            deployments[packageDir] = publishedReceipt;
        }
        objectIds = {
            ...objectIds,
            squid: findObjectId(deployments.squid.publishTxn, 'squid::Squid'),
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
        let type = `${deployments.example.packageId}::a::A`
        coins.a = {
            treasuryCap: findObjectId(deployments.example.publishTxn, `TreasuryCap<${type}>`),
            coinMetadata: findObjectId(deployments.example.publishTxn, `CoinMetadata<${type}>`),
            type,
        };
        type = `${deployments.example.packageId}::b::B`
        coins.b = {
            treasuryCap: findObjectId(deployments.example.publishTxn, `TreasuryCap<${type}>`),
            coinMetadata: findObjectId(deployments.example.publishTxn, `CoinMetadata<${type}>`),
            type,
        };
        type = `${deployments.example.packageId}::c::C`
        coins.c = {
            treasuryCap: findObjectId(deployments.example.publishTxn, `TreasuryCap<${type}>`),
            coinMetadata: findObjectId(deployments.example.publishTxn, `CoinMetadata<${type}>`),
            type,
        };

        // Find the object ids from the publish transactions
        objectIds = {
            ...objectIds,
            itsChannel: await getITSChannelId(client, objectIds.itsV0),
        };

        pools.ab = await createPool('a', 'b');
        pools.bc = await createPool('b', 'c');
        await fundPool('a', 'b', 1000000);

        await setupGateway();
        await registerItsTransaction();
        await setupTrustedAddresses(client, deployer, objectIds, deployments, [trustedSourceAddress], [trustedSourceChain]);
    });

    it('should call register_transaction successfully', async () => {

    });
});
