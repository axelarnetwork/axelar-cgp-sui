require('dotenv').config();
const { TxBuilder } =  require('../dist/tx-builder');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');

describe('test', () => {
    let client, keypair;
    before(async() => {
        client = new SuiClient(getFullnodeUrl('localnet'));
        keypair = new SuiKeypair();
        const builder = new TxBuilder(client);

        const response = await builder.signAndExecute(keypair);
    })
    it('test', async () => {

    });
});