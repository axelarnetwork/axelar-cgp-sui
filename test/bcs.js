const { bcsStructs } = require('../dist/cjs/bcs');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui/client');
const { fromHEX, toHEX } = require('@mysten/bcs');
const { getBcsBytesByObjectId } = require('./testutils');
const { expect } = require('chai');

// The following hex data is derived from the bcs bytes from the client.getObject() call.
const hexData = {
    ITS_v0:
        '7d262a840033c9b6bc7a31d8ddf12bff891c6db6253dd5b8cf331bccd531a81e00000000000000006ccb9729af3569630b9171a0c1fd3eae9797d8122794be5d8cd01061b1dfcb86270c7f8b9757b05777d3cbf98fa1bb197e1f5a18c8ff7a8ef16e80bedf39a67f000000000000000000c101dbc800d8cf853e6d21c916aba7c92e4c2692527dc951c777dae15cf474000000000000000044bacbed87a2d5f871ce96f3245a293b936fb287605330b3859649f3a2697668000000000000000013bd4dc87b61a82ce5959e3ea8c3fed1e03d9c1f7246eef82722354d8e3c0d540000000000000000e5855b758d21f521071672cbce153167d49b4d15f11f5ca47528117312c2c1fa00000000000000000000000000000000000000000000000000000000000000000000000000000000010c0d72656769737465725f636f696e1e6465706c6f795f72656d6f74655f696e746572636861696e5f746f6b656e1873656e645f696e746572636861696e5f7472616e736665721b726563656976655f696e746572636861696e5f7472616e7366657225726563656976655f696e746572636861696e5f7472616e736665725f776974685f646174611f726563656976655f6465706c6f795f696e746572636861696e5f746f6b656e16676976655f756e726567697374657265645f636f696e136d696e745f61735f6469737472696275746f72166d696e745f746f5f61735f6469737472696275746f72136275726e5f61735f6469737472696275746f72157365745f747275737465645f6164647265737365731472656769737465725f7472616e73616374696f6e',
    GatewayV0:
        'c15879de64dc6678674e5ad1a32c47319a1e9100bf21408173590455d01f9d160000000000000000196e295da7fe769ff56d2627c38252ee603f90829ea777bce36ce676b5e3d9d5a7f4b2d4c193987e5f01122bc9cce22a791447d10bc58299ced9e4e18db4c2c503000000000000000100000000000000537d294cfaa7dc649e43cab6a2d829674ea9c11c86517fec9e3984cdedaee42501000000000000000e59feaeb543924fabfbeb667efe707290cf4de9e667796b132260f33a84c26ee803000000000000b23c626b920100000f00000000000000010610617070726f76655f6d657373616765730e726f746174655f7369676e6572731369735f6d6573736167655f617070726f7665641369735f6d6573736167655f65786563757465641574616b655f617070726f7665645f6d6573736167650c73656e645f6d657373616765',
    GasServiceV0:
        '0178ed64520e2e76bfbfc5551ac9b60acc59b00d6148c9db446a9d7462a96eba000000000000000000000000000000000104077061795f676173076164645f6761730b636f6c6c6563745f67617306726566756e64',
    RelayerDiscoveryV0:
        '5dcab278dc93438e0705fc32023808927e09a29b1ae52eef6cb33b9250d9b87100000000000000005339d11ffc9ae10e448b36b776533e1f08c646ad0441c7a0d410b1e0e5d28e58010000000000000001031472656769737465725f7472616e73616374696f6e1272656d6f76655f7472616e73616374696f6e0f6765745f7472616e73616374696f6e',
};

describe('BCS', () => {
    const checkIdAndSize = (obj, expectedId, size = '0') => {
        expect(obj).to.deep.include({ id: expectedId, size });
    };

    it('should decode ITS_v0 object successfully', () => {
        const its = bcsStructs.its.ITS.parse(fromHEX(hexData.ITS_v0)).value;

        checkIdAndSize(its.address_tracker.trusted_addresses, '270c7f8b9757b05777d3cbf98fa1bb197e1f5a18c8ff7a8ef16e80bedf39a67f');
        checkIdAndSize(its.unregistered_coin_types, '00c101dbc800d8cf853e6d21c916aba7c92e4c2692527dc951c777dae15cf474');
        checkIdAndSize(its.unregistered_coins, '44bacbed87a2d5f871ce96f3245a293b936fb287605330b3859649f3a2697668');
        checkIdAndSize(its.registered_coin_types, '13bd4dc87b61a82ce5959e3ea8c3fed1e03d9c1f7246eef82722354d8e3c0d54');
        checkIdAndSize(its.registered_coins, 'e5855b758d21f521071672cbce153167d49b4d15f11f5ca47528117312c2c1fa');

        expect(its.channel.id).to.equal('6ccb9729af3569630b9171a0c1fd3eae9797d8122794be5d8cd01061b1dfcb86');
        expect(its.relayer_discovery_id).to.equal('0x0000000000000000000000000000000000000000000000000000000000000000');

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
            );
        expect(allowedFunctions).to.have.lengthOf(12);
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

        expect(gasServiceV0.id).to.equal('0178ed64520e2e76bfbfc5551ac9b60acc59b00d6148c9db446a9d7462a96eba');
        expect(gasServiceV0.name).to.equal('0');
        expect(gasServiceV0.value.balance).to.equal('0');
        expect(gasServiceV0.value.version_control.allowed_functions[0].contents)
            .to.be.an('array')
            .with.lengthOf(4)
            .that.includes('pay_gas', 'add_gas', 'collect_gas', 'refund');
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
