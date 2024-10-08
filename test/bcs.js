const { bcsStructs } = require('../dist/bcs');
const { fromHEX } = require('@mysten/bcs');
const { expect } = require('chai');

// The following hex data is derived from the bcs bytes from the client.getObject() call.
const hexData = {
    ITSV0: '7d262a840033c9b6bc7a31d8ddf12bff891c6db6253dd5b8cf331bccd531a81e00000000000000006ccb9729af3569630b9171a0c1fd3eae9797d8122794be5d8cd01061b1dfcb86270c7f8b9757b05777d3cbf98fa1bb197e1f5a18c8ff7a8ef16e80bedf39a67f000000000000000000c101dbc800d8cf853e6d21c916aba7c92e4c2692527dc951c777dae15cf474000000000000000044bacbed87a2d5f871ce96f3245a293b936fb287605330b3859649f3a2697668000000000000000013bd4dc87b61a82ce5959e3ea8c3fed1e03d9c1f7246eef82722354d8e3c0d540000000000000000e5855b758d21f521071672cbce153167d49b4d15f11f5ca47528117312c2c1fa00000000000000000000000000000000000000000000000000000000000000000000000000000000010c0d72656769737465725f636f696e1e6465706c6f795f72656d6f74655f696e746572636861696e5f746f6b656e1873656e645f696e746572636861696e5f7472616e736665721b726563656976655f696e746572636861696e5f7472616e7366657225726563656976655f696e746572636861696e5f7472616e736665725f776974685f646174611f726563656976655f6465706c6f795f696e746572636861696e5f746f6b656e16676976655f756e726567697374657265645f636f696e136d696e745f61735f6469737472696275746f72166d696e745f746f5f61735f6469737472696275746f72136275726e5f61735f6469737472696275746f72157365745f747275737465645f6164647265737365731472656769737465725f7472616e73616374696f6e',
};

describe('BCS', () => {
    it('should decode ITS_V0 object successfully', () => {
        const its = bcsStructs.its.ITS.parse(fromHEX(hexData.ITSV0)).value;

        const checkIdAndSize = (obj, expectedId) => {
            expect(obj).to.deep.include({ id: expectedId, size: '0' });
        };

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
});
