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
const { bcs } = require('@mysten/sui/bcs');
const { expect } = require('chai');
const { TxBuilder } = require('../dist/tx-builder');

// TODOO: Remove `only` when finish testing
describe.only('ITS', () => {
    let client;
    let its;
    let example;
    let itsObjectId;
    let singletonObjectId;
    let tokenId;
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
            await publishPackage(client, deployer, packageName);
        }

        its = await publishPackage(client, deployer, 'its');
        example = await publishPackage(client, deployer, 'example');

        itsObjectId = findObjectId(its.publishTxn, 'ITS');
        singletonObjectId = findObjectId(example.publishTxn, 'its_example::Singleton');
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

    it('should deploy remote interchain token successfully', async () => {
        // call deploy remote interchain token
        //const txBuilder = new TxBuilder(client);
        //
        //console.log('arguments', itsObjectId, tokenId, 'Ethereum');
        //const tokenIdObject = await txBuilder.moveCall({
        //    target: `${its.packageId}::token_id::from_u256`,
        //    arguments: [tokenId],
        //});
        //
        //await txBuilder.moveCall({
        //    target: `${its.packageId}::service::deploy_remote_interchain_token`,
        //    arguments: [itsObjectId, tokenIdObject, 'Ethereum'],
        //    typeArguments: [`${example.packageId}::coin::COIN`],
        //});
        //
        //let txResult = await txBuilder.signAndExecute(deployer, {
        //    showEvents: true,
        //});
        //
        //console.log(txResult);
        //console.log(txResult.events[0].parsedJson);
    });
});
