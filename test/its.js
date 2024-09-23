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
const { publishPackage, generateEd25519Keypairs } = require('./testutils');

describe.only('ITS', () => {
    let client;
    let its;
    let example;
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

        // Publish all dependencies
        ['utils', 'version_control', 'gas_service', 'abi', 'axelar_gateway', 'governance'].forEach(async (packageName) => {
            await publishPackage(client, deployer, packageName);
        });

        its = await publishPackage(client, deployer, 'its');
        example = await publishPackage(client, deployer, 'example');
    });

    it('should register a coin successfully', async () => {});
});
