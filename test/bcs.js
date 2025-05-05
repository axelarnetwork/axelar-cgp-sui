const { bcsStructs } = require('../dist/cjs/bcs');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui/client');
const { fromHEX, toHEX } = require('@mysten/bcs');
const { getBcsBytesByObjectId } = require('./testutils');
const { expect } = require('chai');

// The following hex data is derived from the bcs bytes from the client.getObject() call.
const hexData = {
    InterchainTokenService_v0:
        'e167e3f1723e7de7721044908e98167df62b34eec21b225dc4de00733272687f00000000000000007ea12d713858af8412a345c4d17542de4e766a3fdb3f09e06797b18d4051f86dd3268ec782d5973178e2225a3dc2f513244471cdf03213dd343947b709ff41d30000000000000000b9283015c28a199919df7e2665238835c182013b30a4233d6e036cea0d9d373500000000000000008ab0c93b5ca5585b9f3d78f2dafd1e0b43385e5b2a854818a106d338937f178d000000000000000022917e135a1a40a6b43b7776d83513ac797b94496177c9347520ef5431dd12ce0000000000000000bc655c886b535ff1437f28f2717ae3fabdc8a2f040aceebf3dd14a011e744df1000000000000000000000000000000000000000000000000000000000000000000000000000000000b6875625f6164647265737362dcd9931dfd4b454526d130f627854784d12bc67b48810bbe659af1adfd3f5b01110d72656769737465725f636f696e1e6465706c6f795f72656d6f74655f696e746572636861696e5f746f6b656e1873656e645f696e746572636861696e5f7472616e736665721b726563656976655f696e746572636861696e5f7472616e7366657225726563656976655f696e746572636861696e5f7472616e736665725f776974685f646174611f726563656976655f6465706c6f795f696e746572636861696e5f746f6b656e16676976655f756e726567697374657265645f636f696e136d696e745f61735f6469737472696275746f72166d696e745f746f5f61735f6469737472696275746f72136275726e5f61735f6469737472696275746f72126164645f747275737465645f636861696e731572656d6f76655f747275737465645f636861696e731472656769737465725f7472616e73616374696f6e0e7365745f666c6f775f6c696d6974207365745f666c6f775f6c696d69745f61735f746f6b656e5f6f70657261746f720e616c6c6f775f66756e6374696f6e11646973616c6c6f775f66756e6374696f6e',
    GatewayV0:
        'c15879de64dc6678674e5ad1a32c47319a1e9100bf21408173590455d01f9d160000000000000000196e295da7fe769ff56d2627c38252ee603f90829ea777bce36ce676b5e3d9d5a7f4b2d4c193987e5f01122bc9cce22a791447d10bc58299ced9e4e18db4c2c503000000000000000100000000000000537d294cfaa7dc649e43cab6a2d829674ea9c11c86517fec9e3984cdedaee42501000000000000000e59feaeb543924fabfbeb667efe707290cf4de9e667796b132260f33a84c26ee803000000000000b23c626b920100000f00000000000000010610617070726f76655f6d657373616765730e726f746174655f7369676e6572731369735f6d6573736167655f617070726f7665641369735f6d6573736167655f65786563757465641574616b655f617070726f7665645f6d6573736167650c73656e645f6d657373616765',
    GasServiceV0:
        'bcb70c9fabd166e2af35e90048df65bebfea2619c862087aa8dfc4d571b96aeb0000000000000000db70b4c23ee7bc791972273843aa80edfcb47f0db3d3c93afa99f791588cf43101000000000000000106077061795f676173076164645f6761730b636f6c6c6563745f67617306726566756e640e616c6c6f775f66756e6374696f6e11646973616c6c6f775f66756e6374696f6e',
    RelayerDiscoveryV0:
        '5dcab278dc93438e0705fc32023808927e09a29b1ae52eef6cb33b9250d9b87100000000000000005339d11ffc9ae10e448b36b776533e1f08c646ad0441c7a0d410b1e0e5d28e58010000000000000001031472656769737465725f7472616e73616374696f6e1272656d6f76655f7472616e73616374696f6e0f6765745f7472616e73616374696f6e',
};

describe('BCS', () => {
    const checkIdAndSize = (obj, expectedId, size = '0') => {
        expect(obj).to.deep.include({ id: expectedId, size });
    };

    it('should decode InterchainTokenService_v0 object successfully', () => {
        const its = bcsStructs.its.InterchainTokenService.parse(fromHEX(hexData.InterchainTokenService_v0)).value;
        console.log(its.version_control.allowed_functions);
        checkIdAndSize(its.trusted_chains.trusted_chains, 'd3268ec782d5973178e2225a3dc2f513244471cdf03213dd343947b709ff41d3');
        checkIdAndSize(its.unregistered_coin_types, 'b9283015c28a199919df7e2665238835c182013b30a4233d6e036cea0d9d3735');
        checkIdAndSize(its.unregistered_coins, '8ab0c93b5ca5585b9f3d78f2dafd1e0b43385e5b2a854818a106d338937f178d');
        checkIdAndSize(its.registered_coin_types, '22917e135a1a40a6b43b7776d83513ac797b94496177c9347520ef5431dd12ce');
        checkIdAndSize(its.registered_coins, 'bc655c886b535ff1437f28f2717ae3fabdc8a2f040aceebf3dd14a011e744df1');

        expect(its.channel.id).to.equal('7ea12d713858af8412a345c4d17542de4e766a3fdb3f09e06797b18d4051f86d');
        expect(its.its_hub_address).to.equal('hub_address');
        expect(its.chain_name_hash).to.equal('0x62dcd9931dfd4b454526d130f627854784d12bc67b48810bbe659af1adfd3f5b');

        const allowedFunctions = its.version_control.allowed_functions[0].contents;
        expect(allowedFunctions)
            .to.be.an('array')
            .that.includes(
                'register_coin',
                'deploy_remote_interchain_token',
                'send_interchain_transfer',
                'receive_interchain_transfer',
                'receive_interchain_transfer_with_data',
                'receive_deploy_interchain_token',
                'give_unregistered_coin',
                'mint_as_distributor',
                'mint_to_as_distributor',
                'burn_as_distributor',
                'add_trusted_chains',
                'remove_trusted_chains',
                'register_transaction',
                'set_flow_limit',
                'set_flow_limit_as_token_operator',
                'allow_function',
                'disallow_function',
            );
        expect(allowedFunctions).to.have.lengthOf(17);
    });

    it('should decode Gateway_v0 object successfully', () => {
        const gatewayV0 = bcsStructs.gateway.Gateway.parse(fromHEX(hexData.GatewayV0));

        expect(gatewayV0.id).to.equal('c15879de64dc6678674e5ad1a32c47319a1e9100bf21408173590455d01f9d16');
        expect(gatewayV0.name).to.equal('0');
        expect(gatewayV0.value.operator).to.equal('0x196e295da7fe769ff56d2627c38252ee603f90829ea777bce36ce676b5e3d9d5');

        checkIdAndSize(gatewayV0.value.messages, 'a7f4b2d4c193987e5f01122bc9cce22a791447d10bc58299ced9e4e18db4c2c5', '3');

        expect(gatewayV0.value.signers).to.deep.include({
            epoch: '1',
            domain_separator: '0x0e59feaeb543924fabfbeb667efe707290cf4de9e667796b132260f33a84c26e',
            minimum_rotation_delay: '1000',
            last_rotation_timestamp: '1728378453170',
            previous_signers_retention: '15',
        });

        checkIdAndSize(
            gatewayV0.value.signers.epoch_by_signers_hash,
            '537d294cfaa7dc649e43cab6a2d829674ea9c11c86517fec9e3984cdedaee425',
            '1',
        );

        expect(gatewayV0.value.version_control.allowed_functions[0].contents)
            .to.be.an('array')
            .with.lengthOf(6)
            .that.includes(
                'approve_messages',
                'rotate_signers',
                'is_message_approved',
                'is_message_executed',
                'take_approved_message',
                'send_message',
            );
    });

    it('should decode GasService_v0 object successfully', () => {
        const gasServiceV0 = bcsStructs.gasService.GasService.parse(fromHEX(hexData.GasServiceV0));
        expect(gasServiceV0.id).to.equal('bcb70c9fabd166e2af35e90048df65bebfea2619c862087aa8dfc4d571b96aeb');
        expect(gasServiceV0.name).to.equal('0');
        expect(gasServiceV0.value.balances.id).to.equal('db70b4c23ee7bc791972273843aa80edfcb47f0db3d3c93afa99f791588cf431');
        expect(gasServiceV0.value.balances.size).to.equal('1');
        expect(gasServiceV0.value.version_control.allowed_functions[0].contents)
            .to.be.an('array')
            .with.lengthOf(6)
            .that.includes('pay_gas', 'add_gas', 'collect_gas', 'refund', 'allow_function', 'disallow_function');
    });

    it('should decode RelayerDiscovery_v0 object successfully', async () => {
        const RelayerDiscoveryV0 = bcsStructs.relayerDiscovery.RelayerDiscovery.parse(fromHEX(hexData.RelayerDiscoveryV0));

        expect(RelayerDiscoveryV0.id).to.equal('5dcab278dc93438e0705fc32023808927e09a29b1ae52eef6cb33b9250d9b871');
        expect(RelayerDiscoveryV0.name).to.equal('0');
        checkIdAndSize(RelayerDiscoveryV0.value.configurations, '5339d11ffc9ae10e448b36b776533e1f08c646ad0441c7a0d410b1e0e5d28e58', '1');
        expect(RelayerDiscoveryV0.value.version_control.allowed_functions[0].contents)
            .to.be.an('array')
            .with.lengthOf(3)
            .that.includes('register_transaction', 'remove_transaction', 'get_transaction');
    });
});

// This function is used by getting the test data in bytes from the object id
// eslint-disable-next-line @typescript-eslint/no-unused-vars
async function printBytesToDebug(objectId) {
    const client = new SuiClient({ url: getFullnodeUrl('localnet') });
    const bytes = await getBcsBytesByObjectId(client, objectId);
    console.log('bytes', toHEX(bytes));
}
