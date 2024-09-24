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

describe.only('ITS', () => {
    let client;
    let its;
    let example;
    let coin;
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
    });

    it('should register a coin successfully', async () => {
        const itsObjectId = findObjectId(its.publishTxn, 'ITS');

        const txBuilder = new TxBuilder(client);

        const coinInfo = await txBuilder.moveCall({
            target: `${its.packageId}::coin_info::from_info`,
            arguments: ['Coin', 'Symbol', 9, 9],
            typeArguments: [`${example.packageId}::coin::COIN`],
        });

        const coinManagement = await txBuilder.moveCall({
            target: `${its.packageId}::coin_management::new_locked`,
            typeArguments: [`${example.packageId}::coin::COIN`],
        });

        await txBuilder.moveCall({
            target: `${its.packageId}::service::register_coin`,
            arguments: [itsObjectId, coinInfo, coinManagement],
            typeArguments: [`${example.packageId}::coin::COIN`],
        });

        let txResult = await txBuilder.signAndExecute(deployer, {
            showEvents: true,
        });

        expect(txResult.events.length).to.equal(1);
        expect(txResult.events[0].parsedJson.token_id).to.be.not.null;
    });
});
