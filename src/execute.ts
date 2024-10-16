import { fromHEX } from '@mysten/bcs';
import { bcs } from '@mysten/sui/bcs';
import { SuiClient } from '@mysten/sui/client';
import { Keypair } from '@mysten/sui/cryptography';
import { hexlify, keccak256 } from 'ethers/lib/utils';
import { bcsStructs } from './bcs';
// You'll need to import or define these types and functions
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
};

export type GatewayInfo = {
    packageId: string;
    gateway: string;
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
    gateway: { WeightedSigners, MessageToSign, Proof, Message },
} = bcsStructs;

export async function approveTx(client: SuiClient, gatewayInfo: GatewayInfo, messageInfo: MessageInfo): Promise<TxBuilder> {
    const { packageId, gateway, signers, signerKeys, domainSeparator } = gatewayInfo;

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

    const tx = new TxBuilder(client);

    await tx.moveCall({
        target: `${packageId}::gateway::approve_messages`,
        arguments: [gateway, hexlify(messageData), hexlify(encodedProof)],
    });

    return tx;
}
