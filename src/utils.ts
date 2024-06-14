import fs from 'fs';
import { getFullnodeUrl } from '@mysten/sui.js/client';

export function getModuleNameFromSymbol(symbol: string) {
    function isNumber(char: string) {
        return char >= '0' && char <= '9';
    }

    function isLowercase(char: string) {
        return char >= 'a' && char <= 'z';
    }

    function isUppercase(char: string) {
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

export function updateMoveToml(packageName: string, packageId: string, moveDir: string = `${__dirname}/../move`) {
    const path = `${moveDir}/${packageName}/Move.toml`;

    let toml = fs.readFileSync(path, 'utf8');

    const lines = toml.split('\n');

    const versionLineIndex = lines.findIndex((line: string) => line.slice(0, 7) === 'version');

    if (!(lines[versionLineIndex + 1].slice(0, 12) === 'published-at')) {
        lines.splice(versionLineIndex + 1, 0, '');
    }

    lines[versionLineIndex + 1] = `published-at = "${packageId}"`;

    const addressesIndex = lines.findIndex((line: string) => line.slice(0, 11) === '[addresses]');

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

export function parseEnv(arg: string) {
    switch (arg?.toLowerCase()) {
        case 'localnet':
        case 'devnet':
        case 'testnet':
        case 'mainnet':
            return { alias: arg, url: getFullnodeUrl(arg as "localnet" | "devnet" | "testnet" | "mainnet") };
        default:
            return JSON.parse(arg);
    }
}
