import { fromHEX } from '@mysten/bcs';
import { bcs } from '@mysten/sui/bcs';
import { SuiClient, SuiTransactionBlockResponse, SuiTransactionBlockResponseOptions } from '@mysten/sui/client';
import { Keypair } from '@mysten/sui/cryptography';
import { arrayify, hexlify, keccak256 } from 'ethers/lib/utils';
import { bcsStructs } from './bcs';
import { TxBuilder } from './tx-builder';
import { hashMessage, signMessage } from './utils';

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

export type MoveCall = {
    function: {
        package_id: string;
        module_name: string;
        name: string;
    };
    arguments: any[]; // eslint-disable-line @typescript-eslint/no-explicit-any
    type_arguments: string[];
};

const COMMAND_TYPE_APPROVE_MESSAGES = 0;
const {
    gateway: { WeightedSigners, MessageToSign, Proof, Message, Transaction },
} = bcsStructs;

export async function approve(
    client: SuiClient,
    keypair: Keypair,
    gatewayApprovalInfo: GatewayApprovalInfo,
    messageInfo: MessageInfo,
    options: SuiTransactionBlockResponseOptions,
) {
    const { packageId, gateway, signers, signerKeys, domainSeparator } = gatewayApprovalInfo;

    const messageData = bcs.vector(Message).serialize([messageInfo]).toBytes();
    const hashed = hashMessage(messageData, COMMAND_TYPE_APPROVE_MESSAGES);

    const message = MessageToSign.serialize({
        domain_separator: fromHEX(domainSeparator),
        signers_hash: keccak256(WeightedSigners.serialize(signers).toBytes()),
        data_hash: hashed,
    }).toBytes();

    let minSigners = 0;
    let totalWeight = 0;

    for (let i = 0; i < signers.signers.length; i++) {
        totalWeight += signers.signers[i].weight;

        if (totalWeight >= signers.threshold) {
            minSigners = i + 1;
            break;
        }
    }

    const signatures = signMessage(signerKeys.slice(0, minSigners), message);
    const encodedProof = Proof.serialize({
        signers,
        signatures,
    }).toBytes();

    const txBuilder = new TxBuilder(client);

    await txBuilder.moveCall({
        target: `${packageId}::gateway::approve_messages`,
        arguments: [gateway, hexlify(messageData), hexlify(encodedProof)],
    });

    await txBuilder.signAndExecute(keypair, options);
}

function createDiscoveryArguments(discovery: string, destinationId: string): [number[], number[]] {
    const discoveryArg = [0, ...arrayify(discovery)];
    const targetIdArg = [1, ...arrayify(destinationId)];
    return [discoveryArg, targetIdArg];
}

function createInitialMoveCall(discoveryPackageId: string, discoveryArg: number[], targetIdArg: number[]): MoveCall {
    return {
        function: {
            package_id: discoveryPackageId,
            module_name: 'discovery',
            name: 'get_transaction',
        },
        arguments: [discoveryArg, targetIdArg],
        type_arguments: [],
    };
}

async function inspectTransaction(builder: TxBuilder, keypair: Keypair) {
    const resp = await builder.devInspect(keypair.toSuiAddress());

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const txData: any = resp.results?.[0]?.returnValues?.[0]?.[0];
    return Transaction.parse(new Uint8Array(txData));
}

function createApprovedMessageCall(builder: TxBuilder, gatewayInfo: GatewayInfo, messageInfo: MessageInfo) {
    return builder.moveCall({
        target: `${gatewayInfo.packageId}::gateway::take_approved_message`,
        arguments: [
            gatewayInfo.gateway,
            messageInfo.source_chain,
            messageInfo.message_id,
            messageInfo.source_address,
            messageInfo.destination_id,
            messageInfo.payload,
        ],
    });
}

/* eslint-disable @typescript-eslint/no-explicit-any */
async function makeCalls(builder: TxBuilder, moveCalls: MoveCall[], payload: string, ApprovedMessage?: any) {
    const returns: any[][] = [];

    for (const call of moveCalls) {
        const moveCall = buildMoveCall(builder, call, payload, returns, ApprovedMessage);
        const result = builder.tx.moveCall(moveCall);
        returns.push(Array.isArray(result) ? result : [result]);
    }
}

/* eslint-disable @typescript-eslint/no-explicit-any */
function buildMoveCall(builder: TxBuilder, moveCallInfo: MoveCall, payload: string, previousReturns: any[][], ApprovedMessage?: any): any {
    const decodeArgs = (args: any[]): unknown[] =>
        args.map(([argType, ...arg]) => {
            switch (argType) {
                case 0:
                    return builder.tx.object(hexlify(arg));
                case 1:
                    return builder.tx.pure(arrayify(arg));
                case 2:
                    return ApprovedMessage;
                case 3:
                    return builder.tx.pure(bcs.vector(bcs.U8).serialize(arrayify(payload)));
                case 4:
                    return previousReturns[arg[1]][arg[2]];
                default:
                    throw new Error(`Invalid argument prefix: ${argType}`);
            }
        });

    return {
        target: `${moveCallInfo.function.package_id}::${moveCallInfo.function.module_name}::${moveCallInfo.function.name}`,
        arguments: decodeArgs(moveCallInfo.arguments),
        typeArguments: moveCallInfo.type_arguments,
    };
}

export async function execute(
    client: SuiClient,
    keypair: Keypair,
    discoveryInfo: DiscoveryInfo,
    gatewayInfo: GatewayInfo,
    messageInfo: MessageInfo,
    options: SuiTransactionBlockResponseOptions,
): Promise<SuiTransactionBlockResponse> {
    const [discoveryArg, targetIdArg] = createDiscoveryArguments(discoveryInfo.discovery, messageInfo.destination_id);
    let moveCalls = [createInitialMoveCall(discoveryInfo.packageId, discoveryArg, targetIdArg)];

    let isFinal = false;

    while (!isFinal) {
        const builder = new TxBuilder(client);

        await makeCalls(builder, moveCalls, messageInfo.payload);

        const nextTx = await inspectTransaction(builder, keypair);

        isFinal = nextTx.is_final;
        moveCalls = nextTx.move_calls;
    }

    const txBuilder = new TxBuilder(client);

    const ApprovedMessage = await createApprovedMessageCall(txBuilder, gatewayInfo, messageInfo);

    await makeCalls(txBuilder, moveCalls, messageInfo.payload, ApprovedMessage);

    return txBuilder.signAndExecute(keypair, options);
}

export async function approveAndExecute(
    client: SuiClient,
    keypair: Keypair,
    gatewayApprovalInfo: GatewayApprovalInfo,
    discoveryInfo: DiscoveryInfo,
    messageInfo: MessageInfo,
    options: SuiTransactionBlockResponseOptions = {
        showEvents: true,
    },
): Promise<SuiTransactionBlockResponse> {
    await approve(client, keypair, gatewayApprovalInfo, messageInfo, options);
    return execute(client, keypair, discoveryInfo, gatewayApprovalInfo, messageInfo, options);
}
