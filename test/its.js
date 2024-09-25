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
const { publishPackage, clock, generateEd25519Keypairs, findObjectId } = require('./testutils');
const { expect } = require('chai');
const { TxBuilder } = require('../dist/tx-builder');

// TODO: Remove `only` when finish testing
describe.only('ITS', () => {
    let client;
    const deployments = {};
    let objectIds = {};
    const dependencies = ['utils', 'version_control', 'gas_service', 'abi', 'axelar_gateway', 'governance', 'its', 'example'];
    const network = process.env.NETWORK || 'localnet';
    const [operator, deployer, keypair] = generateEd25519Keypairs(3);

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

        objectIds = {
            its: findObjectId(deployments.its.publishTxn, 'ITS'),
            singleton: findObjectId(deployments.example.publishTxn, 'its_example::Singleton'),
            relayerDiscovery: findObjectId(deployments.axelar_gateway.publishTxn, 'RelayerDiscovery'),
            gasService: findObjectId(deployments.gas_service.publishTxn, 'GasService'),
        };

        const txBuilder = new TxBuilder(client);

        // mint some coins
        await txBuilder.moveCall({
            target: `${deployments.example.packageId}::its_example::mint`,
            arguments: [objectIds.singleton, 1e18, deployer.toSuiAddress()],
        });

        const mintResult = await txBuilder.signAndExecute(deployer);
        objectIds.coin = findObjectId(mintResult, 'its_example::ITS_EXAMPLE');
    });

    it('should call register_transaction successfully', async () => {
        const txBuilder = new TxBuilder(client);

        await txBuilder.moveCall({
            target: `${deployments.example.packageId}::its_example::register_transaction`,
            arguments: [objectIds.relayerDiscovery, objectIds.singleton, objectIds.its, clock],
        });

        let txResult = await txBuilder.signAndExecute(deployer);

        const discoveryTx = findObjectId(txResult, 'discovery::Transaction');
        expect(discoveryTx).to.be.not.null;
    });

    it('should register a coin successfully', async () => {
        const txBuilder = new TxBuilder(client);
        await txBuilder.moveCall({
            target: `${deployments.example.packageId}::its_example::register_coin`,
            arguments: [objectIds.singleton, objectIds.its],
        });

        let txResult = await txBuilder.signAndExecute(deployer, {
            showEvents: true,
        });

        objectIds.tokenId = txResult.events[0].parsedJson.token_id.id;

        expect(txResult.events.length).to.equal(1);
        expect(objectIds.tokenId).to.be.not.null;
    });

    it('should send interchain transfer successfully', async () => {
        const txBuilder = new TxBuilder(client);

        const tx = txBuilder.tx;

        const coin = tx.splitCoins(objectIds.coin, [1e9]);
        const gas = tx.splitCoins(tx.gas, [1e8]);

        const TokenId = await txBuilder.moveCall({
            target: `${deployments.its.packageId}::token_id::from_u256`,
            arguments: [objectIds.tokenId],
        });

        const { singleton, its, gasService } = objectIds;

        console.log([singleton, its, gasService, TokenId, coin, 'Ethereum', '0x1234', '0x', deployer.toSuiAddress(), gas, '0x', clock]);

        await txBuilder.moveCall({
            target: `${deployments.example.packageId}::its_example::send_interchain_transfer_call`,
            arguments: [singleton, its, gasService, TokenId, coin, 'Ethereum', '0x1234', '0x', deployer.toSuiAddress(), gas, '0x', clock],
        });

        // TODO: Fix trusted address error
        const txResult = await txBuilder.signAndExecute(deployer);

        console.log(txResult);
    });
});
