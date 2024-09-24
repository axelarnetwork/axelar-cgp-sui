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
const { publishPackage, generateEd25519Keypairs, findObjectId } = require('./testutils');
const { expect } = require('chai');
const { TxBuilder } = require('../dist/tx-builder');

// TODO: Remove `only` when finish testing
describe.only('ITS', () => {
    let client;
    let its;
    let gateway;
    let gasService;
    let example;
    let itsObjectId;
    let coinObjectId;
    let singletonObjectId;
    let relayerDiscoveryId;
    let gasServiceObjectId;
    let tokenId;
    const clock = '0x6';
    const network = process.env.NETWORK || 'localnet';
    const [operator, deployer, keypair] = generateEd25519Keypairs(3);

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

        const dependencies = ['utils', 'version_control', 'gas_service', 'abi', 'axelar_gateway', 'governance'];
        for (const packageName of dependencies) {
            const result = await publishPackage(client, deployer, packageName);
            if (packageName === 'axelar_gateway') {
                gateway = result;
            } else if (packageName === 'gas_service') {
                gasService = result;
            }
        }

        its = await publishPackage(client, deployer, 'its');
        example = await publishPackage(client, deployer, 'example');

        itsObjectId = findObjectId(its.publishTxn, 'ITS');
        singletonObjectId = findObjectId(example.publishTxn, 'its_example::Singleton');
        relayerDiscoveryId = findObjectId(gateway.publishTxn, 'RelayerDiscovery');
        gasServiceObjectId = findObjectId(gasService.publishTxn, 'GasService');

        console.log('minting coins');
        const txBuilder = new TxBuilder(client);

        // mint some coins
        await txBuilder.moveCall({
            target: `${example.packageId}::its_example::mint`,
            arguments: [singletonObjectId, 1e18, deployer.toSuiAddress()],
        });

        const mintResult = await txBuilder.signAndExecute(deployer);
        coinObjectId = findObjectId(mintResult, 'its_example::ITS_EXAMPLE');
        console.log('coinObjectId', coinObjectId);
    });

    it('should call register_transaction successfully', async () => {
        const txBuilder = new TxBuilder(client);

        await txBuilder.moveCall({
            target: `${example.packageId}::its_example::register_transaction`,
            arguments: [relayerDiscoveryId, singletonObjectId, itsObjectId, clock],
        });

        let txResult = await txBuilder.signAndExecute(deployer);

        const discoveryTx = findObjectId(txResult, 'discovery::Transaction');
        expect(discoveryTx).to.be.not.null;
    });

    it('should register a coin successfully', async () => {
        const txBuilder = new TxBuilder(client);
        await txBuilder.moveCall({
            target: `${example.packageId}::its_example::register_coin`,
            arguments: [singletonObjectId, itsObjectId],
        });

        let txResult = await txBuilder.signAndExecute(deployer, {
            showEvents: true,
        });

        tokenId = txResult.events[0].parsedJson.token_id.id;

        expect(txResult.events.length).to.equal(1);
        expect(tokenId).to.be.not.null;
    });

    it('should send interchain transfer successfully', async () => {
        const txBuilder = new TxBuilder(client);

        const tx = txBuilder.tx;

        const coin = tx.splitCoins(coinObjectId, [1e9]);

        const gas = tx.splitCoins(tx.gas, [1e8]);

        const TokenId = await txBuilder.moveCall({
            target: `${its.packageId}::token_id::from_u256`,
            arguments: [tokenId],
        });

        await txBuilder.moveCall({
            target: `${example.packageId}::its_example::send_interchain_transfer_call`,
            arguments: [
                singletonObjectId,
                itsObjectId,
                gasServiceObjectId,
                TokenId,
                coin,
                'Ethereum',
                '0x1234',
                '0x',
                deployer.toSuiAddress(),
                gas,
                '0x',
                clock,
            ],
        });

        // TODO: Fix trusted address error
        const txResult = await txBuilder.signAndExecute(deployer);

        console.log(txResult);
    });
});
