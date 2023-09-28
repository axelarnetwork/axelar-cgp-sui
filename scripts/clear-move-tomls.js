require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { MIST_PER_SUI } = require('@mysten/sui.js/utils');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { execSync } = require('child_process');
const fs = require('fs');
const tmp = require('tmp');




function fillAddresses(toml, address) {
    const lines = toml.split('\n');
    const addressesIndex = lines.findIndex(line => line.slice(0, 11) === '[addresses]');
    for(let i = addressesIndex + 1; i<lines.length; i++) {
        const line = lines[i];
        const eqIndex = line.indexOf('=');
        lines[i] = line.slice(0, eqIndex+1) + ` "${address}"`;
    }
    return lines.join('\n');
}
for(const packageName of ['axelar', 'test']) {
    const toml = fs.readFileSync(`move/${packageName}/Move.toml`, 'utf8');
    fs.writeFileSync(`move/${packageName}/Move.toml`, fillAddresses(toml, '0x0'));
}

