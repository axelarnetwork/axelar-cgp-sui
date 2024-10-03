import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { getFullnodeUrl } from '@mysten/sui/client';
import toml from 'smol-toml';
import { InterchainTokenOptions } from './types';

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

export function newInterchainToken(templateFilePath: string, options: InterchainTokenOptions) {
    let content = fs.readFileSync(templateFilePath, 'utf8');

    const defaultFilePath = path.join(path.dirname(templateFilePath), `${options.symbol.toLowerCase()}.move`);

    const filePath = options.filePath || defaultFilePath;

    const structRegex = new RegExp(`struct\\s+Q\\s+has\\s+drop\\s+{}`, 'g');

    // replace the module name with the token symbol in lowercase
    content = content.replace(/(module\s+)([^:]+)(::)([^;]+)/, `$1interchain_token$3${options.symbol.toLowerCase()}`);

    // replace the struct name with the token symbol in uppercase
    content = content.replace(structRegex, `struct ${options.symbol.toUpperCase()} has drop {}`);

    // replace the witness type with the token symbol in uppercase
    content = content.replace(/(fun\s+init\s*\()witness:\s*Q/, `$1witness: ${options.symbol.toUpperCase()}`);

    // replace the decimals with the given decimals
    content = content.replace(/(witness,\s*)(\d+)/, `$1${options.decimals}`);

    // replace the symbol with the given symbol
    content = content.replace(/(b")(Q)(")/, `$1${options.symbol.toUpperCase()}$3`);

    // replace the name with the given name
    content = content.replace(/(b")(Quote)(")/, `$1${options.name}$3`);

    // replace the generic type with the given symbol
    content = content.replace(/<Q>/g, `<${options.symbol.toUpperCase()}>`);

    return {
        filePath,
        content,
    };
}

/**
 * Get the local dependencies of a package from the Move.toml file.
 * @param packageName The name of the package.
 * @param baseMoveDir The parent directory of the Move.toml file.
 * @returns An array of objects containing the name and path of the local dependencies.
 */
export function getLocalDependencies(packageName: string, baseMoveDir: string) {
    const movePath = `${baseMoveDir}/${packageName}/Move.toml`;

    if (!fs.existsSync(movePath)) {
        throw new Error(`Move.toml file not found for given path: ${movePath}`);
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { dependencies } = toml.parse(fs.readFileSync(movePath, 'utf8')) as any;

    const localDependencies = Object.keys(dependencies).filter((key: string) => dependencies[key].local);

    return localDependencies.map((key: string) => ({
        name: key,
        path: `${baseMoveDir}/${path.resolve(path.dirname(movePath), dependencies[key].local)}`,
    }));
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
