import { fromHEX, toHEX } from '@mysten/bcs';
import type { SerializedBcs } from '@mysten/bcs';
import { bcs } from '@mysten/sui/bcs';
import { TransactionArgument, TransactionObjectInput } from '@mysten/sui/transactions';

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

export enum GatewayMessageType {
    ApproveMessages = 0,
    RotateSigners = 1,
}

export interface DependencyNode extends Dependency {
    dependencies: string[];
}

export const UID = bcs.fixedArray(32, bcs.u8()).transform({
    input: (id: string) => fromHEX(id),
    output: (id: number[]) => toHEX(Uint8Array.from(id)),
});

export type Signer = {
    pub_key: Uint8Array;
    weight: number;
};

export type MessageInfo = {
    source_chain: string;
    message_id: string;
    source_address: string;
    destination_id: string;
    payload_hash: string;
    payload: string;
};

export type GatewayInfo = {
    packageId: string;
    gateway: string;
};

export type GatewayApprovalInfo = GatewayInfo & {
    signers: {
        signers: Signer[];
        threshold: number;
        nonce: string;
    };
    signerKeys: string[];
    domainSeparator: string;
};

export type DiscoveryInfo = {
    packageId: string;
    discovery: string;
};

export type RawMoveCall = {
    function: {
        package_id: string;
        module_name: string;
        name: string;
    };
    arguments: any[]; // eslint-disable-line @typescript-eslint/no-explicit-any
    type_arguments: string[];
};

export type MoveCallArgument = TransactionArgument | SerializedBcs<any>; // eslint-disable-line @typescript-eslint/no-explicit-any

export type MoveCall = {
    arguments?: MoveCallArgument[];
    typeArguments?: string[];
    target: string;
};

export type ApprovedMessage = {
    $kind: string;
    Result: number;
};

export enum MoveCallType {
    Object = 0,
    Pure = 1,
    ApproveMessage = 2,
    Payload = 3,
    HotPotato = 4,
}
