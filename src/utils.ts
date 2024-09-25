import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { getFullnodeUrl } from '@mysten/sui/client';
import toml from 'smol-toml';

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
