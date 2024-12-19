import { TransactionResult } from '@mysten/sui/transactions';
import { Bytes } from 'ethers';
import { TxBuilderBase } from '../common/tx-builder-base';
import { InterchainTokenOptions } from '../common/types';
import { addFile, getContractBuild as getMoveContractBuild, removeFile, writeInterchainToken } from './node-utils';

export class TxBuilder extends TxBuilderBase {
    getContractBuild(
        packageName: string,
        moveDir: string = `${__dirname}/../../move`,
    ): { modules: string[]; dependencies: string[]; digest: Bytes } {
        return getMoveContractBuild(packageName, moveDir);
    }

    async publishInterchainToken(moveDir: string, options: InterchainTokenOptions) {
        const { filePath, templateContent, templateFilePath } = writeInterchainToken(moveDir, options);

        try {
            // temporarily remove the template module to avoid publishing it unnecessarily
            removeFile(templateFilePath);

            return await this.publishPackage('interchain_token', moveDir);
        } finally {
            // remove the created module
            removeFile(filePath);
            // restore the template module
            addFile(templateFilePath, templateContent);
        }
    }

    async publishPackage(packageName: string, moveDir: string = `${__dirname}/../../move`): Promise<TransactionResult> {
        const { modules, dependencies } = this.getContractBuild(packageName, moveDir);

        return this.tx.publish({
            modules,
            dependencies,
        });
    }

    async publishPackageAndTransferCap(packageName: string, to: string, moveDir = `${__dirname}/../../move`) {
        const cap = await this.publishPackage(packageName, moveDir);

        this.tx.transferObjects([cap], to);
    }
}
