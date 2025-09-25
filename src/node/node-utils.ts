import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { Bytes } from 'ethers';
import toml, { TomlValue } from 'smol-toml';
import { Dependency, DependencyNode, InterchainTokenOptions } from '../common/types';

type ChainType = {
    devnet: string;
    testnet: string;
    mainnet: string;
};

const emptyPackageId = '0x0';

const chainIds: ChainType = {
    devnet: 'aba3e445',
    testnet: '4c78adac',
    mainnet: '35834a8a',
};

/**
 * Prepare a move build by creating a temporary directory to store the compiled move code
 * @returns {tmpdir: string, rmTmpDir: () => void}
 * - tmpdir is the path to the temporary directory
 * - rmTmpDir is a function to remove the temporary directory
 */
export function prepareMoveBuild(tmpDir: string) {
    const tmpdir = fs.mkdtempSync(path.join(tmpDir, '.move-build-'));
    const rmTmpDir = () => fs.rmSync(tmpdir, { recursive: true });

    return {
        tmpdir,
        rmTmpDir,
    };
}

export const getInstalledSuiVersion = () => {
    const suiVersion = execSync('sui --version').toString().trim();
    return parseVersion(suiVersion);
};

export const getDefinedSuiVersion = () => {
    const version = fs.readFileSync(`${__dirname}/../../version.json`, 'utf8');
    const suiVersion = JSON.parse(version).SUI_VERSION;
    return parseVersion(suiVersion);
};

const parseVersion = (version: string) => {
    const versionMatch = version.match(/\d+\.\d+\.\d+/);
    return versionMatch?.[0];
};

export function getContractBuild(packageName: string, moveDir: string): { modules: string[]; dependencies: string[]; digest: Bytes } {
    updateMoveToml(packageName, emptyPackageId, moveDir);

    const { tmpdir, rmTmpDir } = prepareMoveBuild(path.dirname(moveDir));

    try {
        const { modules, dependencies, digest } = JSON.parse(
            execSync(`sui move build --dump-bytecode-as-base64 --path ${path.join(moveDir, packageName)} --install-dir ${tmpdir}`, {
                encoding: 'utf-8',
                stdio: 'pipe',
            }),
        );

        return { modules, dependencies, digest };
    } finally {
        rmTmpDir();
    }
}

export function writeInterchainToken(moveDir: string, options: InterchainTokenOptions) {
    const templateFilePath = `${moveDir}/interchain_token/sources/interchain_token.move`;

    const templateContent = fs.readFileSync(templateFilePath, 'utf8');
    const { filePath, content } = newInterchainToken(templateFilePath, options);

    fs.writeFileSync(filePath, content, 'utf8');

    return { templateFilePath, filePath, templateContent };
}

export function removeFile(filePath: string) {
    fs.rmSync(filePath);
}

export function addFile(filePath: string, content: string) {
    fs.writeFileSync(filePath, content, 'utf8');
}

export function updateMoveToml(
    packageName: string,
    packageId: string,
    moveDir: string = `${__dirname}/../../move`,
    prepToml: undefined | ((tomlJson: Record<string, TomlValue>) => Record<string, TomlValue>) = undefined,
    // Version should be the 0 indexed variant (as per axelar-contract-deployments chain config)
    version?: undefined | number,
    network?: undefined | string,
    originalPackageId?: undefined | string,
) {
    if (typeof version !== 'number') {
        version = 0;
    }

    if (typeof network !== 'string') {
        network = 'testnet';
    } else if (network !== 'devnet' && network !== 'testnet' && network !== 'mainnet') {
        throw new Error(`Unsupported chain-id for given network ${network}. Must be one of ${JSON.stringify(chainIds)}`);
    }

    // Path to the Move.toml and Move.lock files for the package
    const movePath = `${moveDir}/${packageName}`;
    const tomlPath = `${movePath}/Move.toml`;
    const lockPath = `${movePath}/Move.lock`;

    // Check if the Move.toml and Move.lock file exists
    if (!fs.existsSync(tomlPath)) {
        throw new Error(`Move.toml file not found for given path: ${tomlPath}`);
    }

    const wasBuilt = fs.existsSync(lockPath);

    // Read the Move.toml file
    const tomlRaw = fs.readFileSync(tomlPath, 'utf8');

    // Parse the Move.toml file as JSON
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let tomlJson: any = toml.parse(tomlRaw);

    // Retire legacy 'published-at' if required
    if (tomlJson.package['published-at']) {
        delete tomlJson.package['published-at'];
    }

    // Reset the package address in the addresses field to '0x0'
    (tomlJson as Record<string, Record<string, string>>).addresses[packageName] = emptyPackageId;

    // If this function was called before publishing on-chain, exit gracefully without updating Move.lock
    // as it would add '0x0' to original-published-id and latest-published-id breaking dependency compilation
    // @see: getContractBuild
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let lockJson: any;

    if (wasBuilt) {
        // Read and parse the Move.lock file
        const lockRaw = fs.readFileSync(lockPath, 'utf8');
        lockJson = toml.parse(lockRaw);

        // Determine original-published-id
        let originalPublishedId = version > 0 ? originalPackageId : packageId;
        // Or, derive existing original-published-id from the lock file
        const noLegacyPkgIdMsg = `Upgrade parameter missing, no original-published-id was found for given path: ${lockPath}`;

        if (!originalPublishedId && lockJson.env) {
            // Fail if no sub-table exists for current network
            try {
                originalPublishedId = lockJson.env[network]['original-published-id'];
            } catch {
                throw new Error(noLegacyPkgIdMsg);
            }
        } else {
            throw new Error(noLegacyPkgIdMsg);
        }

        // Add the required sections for building versioned dependencies
        // [env]
        if (!lockJson.env) {
            lockJson.env = {};
        }

        // [env.devnet], [env.testnet], [env.mainnet]
        lockJson.env[network] = {
            'chain-id': chainIds[network as 'devnet' | 'testnet' | 'mainnet'],
            'original-published-id': originalPublishedId,
            'latest-published-id': packageId,
            'published-version': String(version + 1),
        };
    }

    if (prepToml) {
        tomlJson = prepToml(tomlJson);
    }

    if (lockJson) {
        fs.writeFileSync(lockPath, toml.stringify(lockJson));
    }

    fs.writeFileSync(tomlPath, toml.stringify(tomlJson));
}

export function copyMovePackage(packageName: string, fromDir: null | string, toDir: string) {
    if (fromDir == null) {
        fromDir = `${__dirname}/../../move`;
    }

    if (fs.existsSync(`${toDir}/${packageName}`)) {
        fs.rmSync(`${toDir}/${packageName}`, { recursive: true });
    }

    fs.cpSync(`${fromDir}/${packageName}`, `${toDir}/${packageName}`, { recursive: true });
}

export function newInterchainToken(templateFilePath: string, options: InterchainTokenOptions) {
    let content = fs.readFileSync(templateFilePath, 'utf8');

    const defaultFilePath = path.join(path.dirname(templateFilePath), `${options.symbol.toLowerCase()}.move`);

    const filePath = options.filePath || defaultFilePath;

    const structRegex = new RegExp(`struct\\s+Q\\s+has\\s+drop\\s+{}`, 'g');

    // replace the module name with the token symbol in lowercase
    content = content.replace(/(module\s+)([^:]+)(::)([^{]+)/, `$1interchain_token$3${options.symbol.toLowerCase()}`);

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
export function getLocalDependencies(packageName: string, baseMoveDir: string): Dependency[] {
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
        directory: dependencies[key].local.split('/').slice(-1)[0],
    }));
}

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
export function getDeploymentOrder(packageDir: string, baseMoveDir: string): string[] {
    const dependencyMap: { [key: string]: DependencyNode } = {};

    function recursiveDependencies(pkgDir: string) {
        if (dependencyMap[pkgDir]) {
            return;
        }

        const dependencies = getLocalDependencies(pkgDir, baseMoveDir);

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
