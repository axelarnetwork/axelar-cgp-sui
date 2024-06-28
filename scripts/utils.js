const fs = require('fs');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { getFullnodeUrl } = require('@mysten/sui.js/client');

function getModuleNameFromSymbol(symbol) {
    function isNumber(char) {
        return char >= '0' && char <= '9';
    }

    function isLowercase(char) {
        return char >= 'a' && char <= 'z';
    }

    function isUppercase(char) {
        return char >= 'A' && char <= 'Z';
    }

    let i = 0;
    const length = symbol.length;
    let moduleName = '';

    while (isNumber(symbol[i])) {
        i++;
    }

    while (i < length) {
        const char = symbol[i];

        if (isLowercase(char) || isNumber(char)) {
            moduleName += char;
        } else if (isUppercase(char)) {
            moduleName += char.toLowerCase();
        } else if (char === '_' || char === ' ') {
            moduleName += '_';
        }

        i++;
    }

    return moduleName;
}

async function requestSuiFromFaucet(env, address) {
    try {
        await requestSuiFromFaucetV0({
            // use getFaucetHost to make sure you're using correct faucet address
            // you can also just use the address (see Sui Typescript SDK Quick Start for values)
            host: getFaucetHost(env.alias),
            recipient: address,
        });
    } catch (e) {
        console.log(e);
    }
}

function updateMoveToml(packageName, packageId, moveDir = `${__dirname}/../move`) {
    const path = `${moveDir}/${packageName}/Move.toml`;

    let toml = fs.readFileSync(path, 'utf8');

    const lines = toml.split('\n');

    const versionLineIndex = lines.findIndex((line) => line.slice(0, 7) === 'version');

    if (!(lines[versionLineIndex + 1].slice(0, 12) === 'published-at')) {
        lines.splice(versionLineIndex + 1, 0, '');
    }

    lines[versionLineIndex + 1] = `published-at = "${packageId}"`;

    const addressesIndex = lines.findIndex((line) => line.slice(0, 11) === '[addresses]');

    for (let i = addressesIndex + 1; i < lines.length; i++) {
        const line = lines[i];
        const eqIndex = line.indexOf('=');

        if (
            eqIndex < 0 ||
            line.slice(0, packageName.length) !== packageName ||
            line.slice(packageName.length, eqIndex) !== Array(eqIndex - packageName.length + 1).join(' ')
        ) {
            continue;
        }

        lines[i] = line.slice(0, eqIndex + 1) + ` "${packageId}"`;
    }

    toml = lines.join('\n');

    fs.writeFileSync(path, toml);
}

function parseEnv(arg) {
    switch (arg?.toLowerCase()) {
        case 'localnet':
        case 'devnet':
        case 'testnet':
        case 'mainnet':
            return { alias: arg, url: getFullnodeUrl(arg) };
        default:
            return JSON.parse(arg);
    }
}

module.exports = {
    getModuleNameFromSymbol,
    parseEnv,
    requestSuiFromFaucet,
    updateMoveToml,
};
