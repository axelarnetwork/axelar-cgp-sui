import { fromHEX } from '@mysten/bcs';
import { bcs } from '@mysten/sui/bcs';
import { SuiClient, SuiTransactionBlockResponse, SuiTransactionBlockResponseOptions } from '@mysten/sui/client';
import { Keypair } from '@mysten/sui/cryptography';
import { Transaction as SuiTransaction, TransactionObjectInput } from '@mysten/sui/transactions';
import { arrayify, hexlify, keccak256 } from 'ethers/lib/utils';
import { bcsStructs } from './bcs';
import { TxBuilder } from './tx-builder';
import {
    ApprovedMessage,
    DiscoveryInfo,
    GatewayApprovalInfo,
    GatewayInfo,
    GatewayMessageType,
    MessageInfo,
    MoveCall,
    MoveCallArgument,
    MoveCallType,
    RawMoveCall,
} from './types';
import { hashMessage, signMessage } from './utils';

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
    const hashed = hashMessage(messageData, GatewayMessageType.ApproveMessages);

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

function createInitialMoveCall(discoveryInfo: DiscoveryInfo, destinationId: string): RawMoveCall {
    const { packageId, discovery } = discoveryInfo;
    const discoveryArg = [MoveCallType.Object, ...arrayify(discovery)];
    const targetIdArg = [MoveCallType.Pure, ...arrayify(destinationId)];

    return {
        function: {
            package_id: packageId,
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
function makeCalls(tx: SuiTransaction, moveCalls: RawMoveCall[], payload: string, ApprovedMessage?: ApprovedMessage) {
    const returns: any[][] = [];

    for (const call of moveCalls) {
        const moveCall = buildMoveCall(tx, call, payload, returns, ApprovedMessage);
        const result = tx.moveCall(moveCall);
        returns.push(Array.isArray(result) ? result : [result]);
    }
}

/* eslint-disable @typescript-eslint/no-explicit-any */
function buildMoveCall(
    tx: SuiTransaction,
    moveCallInfo: RawMoveCall,
    payload: string,
    previousReturns: any[][],
    ApprovedMessage?: ApprovedMessage,
): MoveCall {
    const decodeArgs = (args: any[]): MoveCallArgument[] =>
        args.map(([argType, ...arg]) => {
            switch (argType) {
                case MoveCallType.Object:
                    return tx.object(hexlify(arg));
                case MoveCallType.Pure:
                    return tx.pure(arrayify(arg));
                case MoveCallType.ApproveMessage:
                    return ApprovedMessage;
                case MoveCallType.Payload:
                    return tx.pure(bcs.vector(bcs.U8).serialize(arrayify(payload)));
                case MoveCallType.HotPotato:
                    return previousReturns[arg[1]][arg[2]];
                default:
                    throw new Error(`Invalid argument prefix: ${argType}`);
            }
        });

    const { package_id: packageId, module_name: moduleName, name } = moveCallInfo.function;

    return {
        target: `${packageId}::${moduleName}::${name}`,
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
    let moveCalls = [createInitialMoveCall(discoveryInfo, messageInfo.destination_id)];

    let isFinal = false;

    while (!isFinal) {
        const builder = new TxBuilder(client);

        makeCalls(builder.tx, moveCalls, messageInfo.payload);

        const nextTx = await inspectTransaction(builder, keypair);

        isFinal = nextTx.is_final;
        moveCalls = nextTx.move_calls;
    }

    const txBuilder = new TxBuilder(client);

    const ApprovedMessage = await createApprovedMessageCall(txBuilder, gatewayInfo, messageInfo);

    makeCalls(txBuilder.tx, moveCalls, messageInfo.payload, ApprovedMessage);

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
