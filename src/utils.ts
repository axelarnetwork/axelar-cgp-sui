import { execSync } from 'child_process';
import fs from 'fs';
import { getFullnodeUrl } from '@mysten/sui/client';
import toml from 'smol-toml';

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
    // Path to the Move.toml file for the package
    const movePath = `${moveDir}/${packageName}/Move.toml`;

    // Check if the Move.toml file exists
    if (!fs.existsSync(movePath)) {
        throw new Error(`Move.toml file not found for given path: ${movePath}`);
    }

    // Read the Move.toml file
    const moveRaw = fs.readFileSync(movePath, 'utf8');

    // Parse the Move.toml file as JSON
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const moveJson = toml.parse(moveRaw) as any;

    // Update the published-at field under the package section e.g. published-at = "0x01"
    moveJson.package['published-at'] = packageId;

    // Update the package address under the addresses section e.g. gas_service = "0x1"
    moveJson.addresses[packageName] = packageId;

    fs.writeFileSync(movePath, toml.stringify(moveJson));
}

export function copyMovePackage(packageName: string, fromDir: null | string, toDir: string) {
    if (fromDir == null) {
        fromDir = `${__dirname}/../move`;
    }

    fs.cpSync(`${fromDir}/${packageName}`, `${toDir}/${packageName}`, { recursive: true });
}

export const getInstalledSuiVersion = () => {
    const suiVersion = execSync('sui --version').toString().trim();
    return parseVersion(suiVersion);
};

export const getDefinedSuiVersion = () => {
    const version = fs.readFileSync(`${__dirname}/../version.json`, 'utf8');
    const suiVersion = JSON.parse(version).SUI_VERSION;
    return parseVersion(suiVersion);
};

const parseVersion = (version: string) => {
    const versionMatch = version.match(/\d+\.\d+\.\d+/);
    return versionMatch?.[0];
};

export function parseEnv(arg: string) {
    switch (arg?.toLowerCase()) {
        case 'localnet':
        case 'devnet':
        case 'testnet':
        case 'mainnet':
            return { alias: arg, url: getFullnodeUrl(arg as 'localnet' | 'devnet' | 'testnet' | 'mainnet') };
        default:
            return JSON.parse(arg);
    }
}
