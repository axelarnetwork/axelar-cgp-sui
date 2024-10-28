import { TransactionResult } from '@mysten/sui/transactions';
import { Bytes } from 'ethers';
import { TxBuilderBase } from '../common/tx-builder-base';
import { InterchainTokenOptions } from '../common/types';
import { getContractBuild as getMoveContractBuild, removeFile, writeInterchainToken } from './node-utils';
import { execSync } from 'child_process';

export class TxBuilder extends TxBuilderBase {
    getContractBuild(
        packageName: string,
        moveDir: string = `${__dirname}/../../move`,
    ): { modules: string[]; dependencies: string[]; digest: Bytes } {
        return getMoveContractBuild(packageName, moveDir);
    }

    async publishInterchainToken(moveDir: string, options: InterchainTokenOptions) {
        const filePath = writeInterchainToken(moveDir, options);

        const publishReceipt = await this.publishPackage('interchain_token', moveDir);

        removeFile(filePath);

        return publishReceipt;
    }

    async publishPackage(packageName: string, moveDir: string = `${__dirname}/../../move`): Promise<TransactionResult> {
        console.log(packageName, moveDir);
        const { modules, dependencies } = this.getContractBuild(packageName, moveDir);

        return this.tx.publish({
            modules,
            dependencies,
        });
    }

    async publishPackageAndTransferCap(packageName: string, to: string, moveDir = `${__dirname}/../../move`) {
        const cap = await this.publishPackage(packageName, moveDir);
        console.log(execSync(`cat ${__dirname}/../../move_compile/${packageName}/Move.toml`, {
            encoding: 'utf-8',
            stdio: 'pipe',
        }));
        this.tx.transferObjects([cap], to);
    }
}
