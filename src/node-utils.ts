import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { Bytes } from 'ethers';
import { InterchainTokenOptions } from './types';
import { newInterchainToken, updateMoveToml } from './utils';

/**
 * Prepare a move build by creating a temporary directory to store the compiled move code
 * @returns {tmpdir: string, rmTmpDir: () => void}
 * - tmpdir is the path to the temporary directory
 * - rmTmpDir is a function to remove the temporary directory
 */
export async function prepareMoveBuild(tmpDir: string) {
    const tmpdir = fs.mkdtempSync(path.join(tmpDir, '.move-build-'));
    const rmTmpDir = () => fs.rmSync(tmpdir, { recursive: true });

    return {
        tmpdir,
        rmTmpDir,
    };
}

export async function getContractBuild(
    packageName: string,
    moveDir: string,
): Promise<{ modules: string[]; dependencies: string[]; digest: Bytes }> {
    const emptyPackageId = '0x0';
    updateMoveToml(packageName, emptyPackageId, moveDir);

    const { tmpdir, rmTmpDir } = await prepareMoveBuild(path.dirname(moveDir));

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

    const { filePath, content } = newInterchainToken(templateFilePath, options);

    fs.writeFileSync(filePath, content, 'utf8');

    return filePath;
}

export function removeFile(filePath: string) {
    fs.rmSync(filePath);
}
