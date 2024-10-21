import { getFullnodeUrl } from '@mysten/sui/client';
import { getFaucetHost, requestSuiFromFaucetV0 } from '@mysten/sui/faucet';
import { arrayify, keccak256 } from 'ethers/lib/utils';
import secp256k1 from 'secp256k1';
import { Dependency, DependencyNode } from './types';

let nodeUtils: typeof import('./node-utils') | undefined;

export const isNode = !!process?.versions?.node;

if (isNode) {
    import('./node-utils').then((module) => {
        nodeUtils = module;
    });
}

export const NODE_ERROR_MESSAGE = 'This operation is only supported in a Node.js environment';

/**
 * Determines the deployment order of Move packages based on their dependencies.
 *
 * @param packageDir - The directory of the main package to start the dependency resolution from.
 * @param baseMoveDir - The base directory where all Move packages are located.
 * @returns An array of package directory names in the order they should be deployed.
 *          The array is sorted such that packages with no dependencies come first,
 *          followed by packages whose dependencies have already appeared in the array.
 *
 * @description
 * This function performs the following steps:
 * 1. Recursively builds a dependency map starting from the given package.
 * 2. Performs a topological sort on the dependency graph.
 * 3. Returns the sorted list of package directories.
 *
 * The function handles circular dependencies and will include each package only once in the output.
 * If a package has multiple dependencies, it will appear in the list after all its dependencies.
 *
 * @example
 * const deploymentOrder = getDeploymentOrder('myPackage', '/path/to/move');
 * console.log(deploymentOrder);
 * Might output: ['dependency1', 'dependency2', 'myPackage']
 */
export async function getDeploymentOrder(packageDir: string, baseMoveDir: string): Promise<string[]> {
    const dependencyMap: { [key: string]: DependencyNode } = {};

    async function recursiveDependencies(pkgDir: string) {
        if (!nodeUtils) throw new Error(NODE_ERROR_MESSAGE);

        if (dependencyMap[pkgDir]) {
            return;
        }

        const dependencies = await nodeUtils.getLocalDependencies(pkgDir, baseMoveDir);

        dependencyMap[pkgDir] = {
            name: pkgDir,
            directory: pkgDir,
            path: `${baseMoveDir}/${pkgDir}`,
            dependencies: dependencies.map((dep) => dep.directory),
        };

        for (const dependency of dependencies) {
            recursiveDependencies(dependency.directory);
        }
    }

    recursiveDependencies(packageDir);

    // Topological sort
    const sorted: Dependency[] = [];
    const visited: { [key: string]: boolean } = {};

    function visit(name: string) {
        if (visited[name]) {
            return;
        }

        visited[name] = true;

        const node = dependencyMap[name];

        for (const depName of node.dependencies) {
            visit(depName);
        }

        sorted.push(node);
    }

    for (const name in dependencyMap) {
        visit(name);
    }

    return sorted.map((dep) => dep.directory);
}

export const fundAccountsFromFaucet = async (addresses: string[]) => {
    const promises = addresses.map(async (address) => {
        const network = process.env.NETWORK || 'localnet';

        return requestSuiFromFaucetV0({
            host: getFaucetHost(network as 'localnet' | 'devnet' | 'testnet'),
            recipient: address,
        });
    });

    return Promise.all(promises);
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

export function hashMessage(data: Uint8Array, commandType: number) {
    const toHash = new Uint8Array(data.length + 1);
    toHash[0] = commandType;
    toHash.set(data, 1);

    return keccak256(toHash);
}

export function signMessage(privKeys: string[], messageToSign: Uint8Array) {
    const signatures = [];

    for (const privKey of privKeys) {
        const { signature, recid } = secp256k1.ecdsaSign(arrayify(keccak256(messageToSign)), arrayify(privKey));
        signatures.push(new Uint8Array([...signature, recid]));
    }

    return signatures;
}
