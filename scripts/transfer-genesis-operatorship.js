require('dotenv').config();
const { transferOperatorship, getAmplifierWorkers } = require("./gateway");
const { SuiClient } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const fs = require('fs');
const { parseEnv } = require('./utils');

(async () => {
    const env = parseEnv(process.argv[2] || 'localnet');
    const rpc = process.argv[3] || 'http://localhost:26657';
    const proverAddr = process.argv[4];
    const allInfo = require(`../info/axelar.json`);
    const privKey = Buffer.from(
        process.env.SUI_PRIVATE_KEY,
        "hex"
    );

    // get the public key in a compressed format
    const keypair = Ed25519Keypair.fromSecretKey(privKey);
    // create a new SuiClient object pointing to the network you want to use
    const client = new SuiClient({ url: env.url });

    const operators = await getAmplifierWorkers(rpc, proverAddr);

    await transferOperatorship(allInfo[env.alias], client, keypair, operators.pubKeys, operators.weights, operators.threshold);

    allInfo[env.alias].activeOperators = operators

    fs.writeFileSync(`info/axelar.json`, JSON.stringify(allInfo, null, 4));
})();