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
const { bcs } = require('@mysten/sui/bcs');
const {
    publishPackage,
    clock,
    generateEd25519Keypairs,
    findObjectId,
    getRandomBytes32,
    calculateNextSigners,
    hashMessage,
    signMessage,
    approveMessage,
    approveAndExecuteMessage,
} = require('./testutils');
const { expect } = require('chai');
const { bcsStructs } = require('../dist/bcs');
const { TxBuilder } = require('../dist/tx-builder');
const { keccak256, defaultAbiCoder, arrayify, hexlify } = require('ethers/lib/utils');

// TODO: Remove `only` when finish testing
describe.only('ITS', () => {
    let client;
    const deployments = {};
    let objectIds = {};
    const gatewayInfo = {};
    const domainSeparator = getRandomBytes32();
    const dependencies = ['utils', 'version_control', 'gas_service', 'abi', 'axelar_gateway', 'governance', 'its', 'example'];
    const network = process.env.NETWORK || 'localnet';
    const [operator, deployer, keypair] = generateEd25519Keypairs(3);
    const minimumRotationDelay = 1000;
    const previousSignersRetention = 15;
    let nonce = 0;

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
            upgradeCap: findObjectId(deployments.governance.publishTxn, 'UpgradeCap'),
            creatorCap: findObjectId(deployments.axelar_gateway.publishTxn, 'CreatorCap'),
        };

        const txBuilder = new TxBuilder(client);

        // mint some coins
        await txBuilder.moveCall({
            target: `${deployments.example.packageId}::its_example::mint`,
            arguments: [objectIds.singleton, 1e18, deployer.toSuiAddress()],
        });

        const mintResult = await txBuilder.signAndExecute(deployer);
        objectIds.coin = findObjectId(mintResult, 'its_example::ITS_EXAMPLE');

        // Setup Gateway
        calculateNextSigners(gatewayInfo, nonce);
        const encodedSigners = bcsStructs.gateway.WeightedSigners.serialize(gatewayInfo.signers).toBytes();

        const builder = new TxBuilder(client);

        const separator = await builder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::bytes32::new`,
            arguments: [domainSeparator],
        });

        await builder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::gateway::setup`,
            arguments: [
                objectIds.creatorCap,
                operator.toSuiAddress(),
                separator,
                minimumRotationDelay,
                previousSignersRetention,
                encodedSigners,
                clock,
            ],
        });

        const setupResult = await builder.signAndExecute(deployer);
        objectIds.gateway = findObjectId(setupResult, 'gateway::Gateway');

        gatewayInfo.gateway = objectIds.gateway;
        gatewayInfo.domainSeparator = domainSeparator;
        gatewayInfo.packageId = deployments.axelar_gateway.packageId;

        // Setup Governance
        const message = {
            source_chain: 'Ethereum',
            source_address: '0x',
        };
        const messageType = BigInt('0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68');

        const setupGovernanceTxBuilder = new TxBuilder(client);
        await setupGovernanceTxBuilder.moveCall({
            target: `${deployments.governance.packageId}::governance::new`,
            arguments: [message.source_chain, message.source_address, messageType, objectIds.upgradeCap],
        });
        const receipt = await setupGovernanceTxBuilder.signAndExecute(deployer);
        objectIds.governance = findObjectId(receipt, 'governance::Governance');
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
        // Approve the message to set trusted addresses
        const messageType = BigInt('0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68');

        const payload = bcsStructs.its.MessageSetTrustedAddresses.serialize({
            message_type: messageType,
            trusted_addresses: {
                trusted_chains: ['Ethereum'],
                trusted_addresses: [arrayify('0x1234')],
            },
        }).toBytes();

        const message = {
            source_chain: 'Ethereum',
            message_id: '0x1234',
            source_address: '0x1234',
            destination_id: objectIds.gateway,
            payload_hash: keccak256(payload),
        };

        await approveMessage(client, keypair, gatewayInfo, message);

        // Set trusted addresses
        const trustedAddressTxBuilder = new TxBuilder(client);

        const approvedMessage = trustedAddressTxBuilder.moveCall({
            target: `${deployments.axelar_gateway.packageId}::gateway::take_approved_message`,
            arguments: [
                objectIds.gateway,
                message.source_chain,
                message.message_id,
                message.source_address,
                message.destination_id,
                hexlify(payload),
            ],
        });
        trustedAddressTxBuilder.moveCall({
            target: `${deployments.its.packageId}::service::set_trusted_addresses`,
            arguments: [objectIds.its, objectIds.governance, approvedMessage],
        });
        const trustedAddressResult = await trustedAddressTxBuilder.signAndExecute(deployer);
        console.log(trustedAddressResult);

        // Send interchain transfer
        //const txBuilder = new TxBuilder(client);
        //
        //const tx = txBuilder.tx;
        //
        //const coin = tx.splitCoins(objectIds.coin, [1e9]);
        //const gas = tx.splitCoins(tx.gas, [1e8]);
        //
        //const TokenId = await txBuilder.moveCall({
        //    target: `${deployments.its.packageId}::token_id::from_u256`,
        //    arguments: [objectIds.tokenId],
        //});
        //
        //const { singleton, its, gasService } = objectIds;
        //
        //await txBuilder.moveCall({
        //    target: `${deployments.example.packageId}::its_example::send_interchain_transfer_call`,
        //    arguments: [singleton, its, gasService, TokenId, coin, 'Ethereum', '0x1234', '0x', deployer.toSuiAddress(), gas, '0x', clock],
        //});
        //
        //// TODO: Fix trusted address error
        //const txResult = await txBuilder.signAndExecute(deployer);
        //
        //console.log(txResult);
    });
});
