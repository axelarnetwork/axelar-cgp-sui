require('dotenv').config();
const { transferOperatorship, getRandomOperators } = require("./gateway");
const secp256k1 = require('secp256k1');
const {BCS, fromHEX, getSuiMoveConfig} = require("@mysten/bcs");
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const axelarInfo = require('../info/axelar.json');
const { keccak256 } = require("ethers/lib/utils");
const fs = require('fs');

(async () => {
    const privKey = Buffer.from(
        process.env.SUI_PRIVATE_KEY,
        "hex"
    );

    // get the public key in a compressed format
    const keypair = Ed25519Keypair.fromSecretKey(privKey);
    // create a new SuiClient object pointing to the network you want to use
    const client = new SuiClient({ url: getFullnodeUrl('localnet') });

    const operators = getRandomOperators(5);

    await transferOperatorship(client, keypair, operators.pubKeys, operators.weights, operators.threashold);

    axelarInfo.activeOperators = operators

    fs.writeFileSync(`info/axelar.json`, JSON.stringify(axelarInfo, null, 4));
})();