const { bcs } = require('@mysten/sui/bcs');
const { fromHEX, toHEX } = require('@mysten/bcs');

export const SUI_PACKAGE_ID = '0x2';
export const STD_PACKAGE_ID = '0x1';
export const CLOCK_PACKAGE_ID = '0x6';

export interface InterchainTokenOptions {
    filePath?: string;
    symbol: string;
    name: string;
    decimals: number;
}

export interface Dependency {
    name: string;
    directory: string;
    path: string;
}

export enum ITSMessageType {
    InterchainTokenTransfer = 0,
    InterchainTokenDeployment = 1,
}

export interface DependencyNode extends Dependency {
    dependencies: string[];
}

export const UID = bcs.fixedArray(32, bcs.u8()).transform({
    input: (id: string) => fromHEX(id),
    output: (id: number[]) => toHEX(Uint8Array.from(id)),
});
