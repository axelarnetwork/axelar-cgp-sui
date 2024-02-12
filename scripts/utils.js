const { arrayify } = require('ethers/lib/utils');
const { getFullnodeUrl } = require('@mysten/sui.js/client');

function toPure(hexString) {
    return String.fromCharCode(...arrayify(hexString));
}

function parseEnv(arg) {
    switch (arg?.toLowerCase()) {
        case 'localnet':
        case 'devnet':
        case 'testnet':
        case 'mainnet':
            return {alias: arg, url: getFullnodeUrl(arg)};
        default:
            return JSON.parse(arg);
  }
}

module.exports = {
    toPure,
    parseEnv,
}