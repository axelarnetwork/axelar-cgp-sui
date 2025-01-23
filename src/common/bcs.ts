import { bcs, BcsType } from '@mysten/sui/bcs';
import { SuiClient, SuiMoveNormalizedType } from '@mysten/sui/dist/cjs/client';
import { UID } from './types';
import { isString } from './utils';

function getCommonStructs() {
    const Bytes32 = bcs.Address;

    const Channel = bcs.struct('Channel', {
        id: UID,
    });

    const Bag = bcs.struct('Bag', {
        id: UID,
        size: bcs.U64,
    });

    const CoinBag = bcs.struct('CoinBag', {
        bag: Bag,
    });

    const DiscoveryTable = bcs.struct('DiscoveryTable', {
        id: UID,
    });

    const Discovery = bcs.struct('Discovery', {
        id: UID,
        fields: DiscoveryTable,
    });

    const Table = bcs.struct('Table', {
        id: UID,
        size: bcs.U64,
    });

    return {
        Bytes32,
        Channel,
        Bag,
        CoinBag,
        DiscoveryTable,
        Discovery,
        Table,
    };
}

function getVersionControlStructs() {
    const VecSet = bcs.struct('VecSet', {
        contents: bcs.vector(bcs.string()),
    });

    const VersionControl = bcs.struct('VersionControl', {
        allowed_functions: bcs.vector(VecSet),
    });

    return {
        VersionControl,
    };
}

function getGatewayStructs() {
    const { Bytes32, Bag, Table } = getCommonStructs();
    const { VersionControl } = getVersionControlStructs();

    const Message = bcs.struct('Message', {
        source_chain: bcs.String,
        message_id: bcs.String,
        source_address: bcs.String,
        destination_id: bcs.Address,
        payload_hash: Bytes32,
    });

    const WeightedSigner = bcs.struct('WeightedSigner', {
        pub_key: bcs.vector(bcs.U8),
        weight: bcs.U128,
    });

    const WeightedSigners = bcs.struct('WeightedSigners', {
        signers: bcs.vector(WeightedSigner),
        threshold: bcs.U128,
        nonce: Bytes32,
    });

    const Signature = bcs.vector(bcs.U8);

    const Proof = bcs.struct('Proof', {
        signers: WeightedSigners,
        signatures: bcs.vector(Signature),
    });

    const MessageToSign = bcs.struct('MessageToSign', {
        domain_separator: Bytes32,
        signers_hash: Bytes32,
        data_hash: Bytes32,
    });

    const Function = bcs.struct('Function', {
        package_id: bcs.Address,
        module_name: bcs.String,
        name: bcs.String,
    });

    /// Arguments are prefixed with:
    /// - 0 for objects followed by exactly 32 bytes that cointain the object id
    /// - 1 for pures followed by the bcs encoded form of the pure
    /// - 2 for the call contract object, followed by nothing (to be passed into the target function)
    /// - 3 for the payload of the contract call (to be passed into the intermediate function)
    /// - 4 for an argument returned from a previous move call, followed by a u8 specified which call to get the return of (0 for the first transaction AFTER the one that gets ApprovedMessage out), and then another u8 specifying which argument to input.
    const MoveCall = bcs.struct('MoveCall', {
        function: Function,
        arguments: bcs.vector(bcs.vector(bcs.U8)),
        type_arguments: bcs.vector(bcs.String),
    });

    const Transaction = bcs.struct('Transaction', {
        is_final: bcs.Bool,
        move_calls: bcs.vector(MoveCall),
    });

    const EncodedMessage = bcs.struct('EncodedMessage', {
        message_type: bcs.U8,
        data: bcs.vector(bcs.U8),
    });

    const Operators = bcs.struct('Operators', {
        id: UID,
        operators: bcs.vector(bcs.Address),
        caps: Bag,
    });

    const ExecuteData = bcs.struct('ExecuteData', {
        payload: bcs.vector(bcs.U8),
        proof: bcs.vector(bcs.U8),
    });

    const ApprovedMessage = bcs.struct('ApprovedMessage', {
        source_chain: bcs.String,
        message_id: bcs.String,
        source_address: bcs.String,
        destination_id: Bytes32,
        payload: bcs.vector(bcs.U8),
    });

    const AxelarSigners = bcs.struct('AxelarSigners', {
        epoch: bcs.U64,
        epoch_by_signers_hash: Table,
        domain_separator: Bytes32,
        minimum_rotation_delay: bcs.U64,
        last_rotation_timestamp: bcs.U64,
        previous_signers_retention: bcs.U64,
    });

    const GatewayV0 = bcs.struct('Gateway_v0', {
        operator: bcs.Address,
        messages: Table,
        signers: AxelarSigners,
        version_control: VersionControl,
    });

    const Gateway = bcs.struct('Gateway', {
        id: UID,
        name: bcs.U64,
        value: GatewayV0,
    });

    return {
        Bytes32,
        Message,
        WeightedSigner,
        WeightedSigners,
        Signature,
        Proof,
        MessageToSign,
        Function,
        MoveCall,
        Transaction,
        EncodedMessage,
        Bag,
        Operators,
        ExecuteData,
        ApprovedMessage,
        Gateway,
    };
}

function getSquidStructs() {
    const { Channel, CoinBag } = getCommonStructs();
    const { VersionControl } = getVersionControlStructs();

    const SwapType = bcs.enum('SwapType', {
        DeepbookV3: null,
        SuiTransfer: null,
        ItsTransfer: null,
    });

    const DeepbookV3SwapData = bcs.struct('DeepbookV3SwapData', {
        swap_type: SwapType,
        pool_id: bcs.Address,
        has_base: bcs.Bool,
        min_output: bcs.U64,
        base_type: bcs.String,
        quote_type: bcs.String,
        lot_size: bcs.U64,
        should_sweep: bcs.Bool,
    });

    const SuiTransferSwapData = bcs.struct('SuiTransferSwapData', {
        swap_type: SwapType,
        coin_type: bcs.String,
        recipient: bcs.Address,
        fallback: bcs.Bool,
    });

    const ItsTransferSwapData = bcs.struct('ItsTransferSwapData', {
        swap_type: SwapType,
        coin_type: bcs.String,
        token_id: bcs.Address,
        destination_chain: bcs.String,
        destination_address: bcs.vector(bcs.U8),
        metadata: bcs.vector(bcs.U8),
        fallback: bcs.Bool,
    });

    const SquidV0 = bcs.struct('Squid_v0', {
        channel: Channel,
        coin_bag: CoinBag,
        version_control: VersionControl,
    });

    const Squid = bcs.struct('Squid', {
        id: UID,
        name: bcs.U64,
        value: SquidV0,
    });

    return {
        SwapType,
        DeepbookV3SwapData,
        SuiTransferSwapData,
        ItsTransferSwapData,
        Squid,
    };
}

function getRelayerDiscoveryStructs() {
    const { Table } = getCommonStructs();
    const { VersionControl } = getVersionControlStructs();

    const RelayerDiscoveryV0 = bcs.struct('RelayerDiscovery_v0', {
        configurations: Table,
        version_control: VersionControl,
    });

    const RelayerDiscovery = bcs.struct('RelayerDiscovery', {
        id: UID,
        name: bcs.U64,
        value: RelayerDiscoveryV0,
    });

    return {
        RelayerDiscovery,
    };
}

function getITSStructs() {
    const { Table, Bag, Channel } = getCommonStructs();
    const { VersionControl } = getVersionControlStructs();

    const InterchainAddressTracker = bcs.struct('InterchainAddressTracker', {
        trusted_addresses: Table,
    });

    const TrustedAddresses = bcs.struct('TrustedAddresses', {
        trusted_chains: bcs.vector(bcs.string()),
        trusted_addresses: bcs.vector(bcs.string()),
    });

    const InterchainTokenServiceV0 = bcs.struct('InterchainTokenService_v0', {
        channel: Channel,
        address_tracker: InterchainAddressTracker,
        unregistered_coin_types: Table,
        unregistered_coins: Bag,
        registered_coin_types: Table,
        registered_coins: Bag,
        relayer_discovery_id: bcs.Address,
        version_control: VersionControl,
    });

    const InterchainTokenService = bcs.struct('InterchainTokenService', {
        id: UID,
        name: bcs.u64(),
        value: InterchainTokenServiceV0,
    });

    return {
        InterchainAddressTracker,
        InterchainTokenService,
        TrustedAddresses,
    };
}

function getGMPStructs() {
    const { Channel } = getCommonStructs();

    const Singleton = bcs.struct('Singleton', {
        id: UID,
        channel: Channel,
    });

    return {
        Singleton,
    };
}

function getGasServiceStructs() {
    const { VersionControl } = getVersionControlStructs();

    const GasServiceV0 = bcs.struct('GasService_v0', {
        balance: bcs.U64,
        version_control: VersionControl,
    });

    const GasService = bcs.struct('GasService', {
        id: UID,
        name: bcs.U64,
        value: GasServiceV0,
    });

    return {
        GasService,
    };
}

export async function getBcsForStruct(
    client: SuiClient,
    type: SuiMoveNormalizedType,
    typeArguments: SuiMoveNormalizedType[] = [],
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<BcsType<any, any>> {
    switch (type) {
        case 'Address':
            return bcs.Address;
        case 'Bool':
            return bcs.Bool;
        case 'U8':
            return bcs.U8;
        case 'U16':
            return bcs.U16;
        case 'U32':
            return bcs.U32;
        case 'U64':
            return bcs.U64;
        case 'U128':
            return bcs.U128;
        case 'U256':
            return bcs.U256;

        default: {
        }
    }

    if (isString(type)) {
        return bcs.String;
    }

    if ('Vector' in (type as object)) {
        return bcs.vector(await getBcsForStruct(client, (type as { Vector: SuiMoveNormalizedType }).Vector, typeArguments));
    }

    if ('Struct' in (type as object)) {
        const structType = (
            type as {
                Struct: {
                    address: string;
                    module: string;
                    name: string;
                    typeArguments: SuiMoveNormalizedType[];
                };
            }
        ).Struct;
        const struct = await client.getNormalizedMoveStruct({
            package: structType.address,
            module: structType.module,
            struct: structType.name,
        });
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const fields: Record<any, any> = {};

        for (const field of struct.fields) {
            fields[field.name] = await getBcsForStruct(client, field.type, structType.typeArguments);
        }

        return bcs.struct(structType.name, fields);
    }

    if ('TypeParameter' in (type as object)) {
        const index = (type as { TypeParameter: number }).TypeParameter;
        return await getBcsForStruct(client, typeArguments[index], typeArguments);
    }

    throw new Error(`Unsupported type ${type}`);
}

export const bcsStructs = {
    common: getCommonStructs(),
    gateway: getGatewayStructs(),
    squid: getSquidStructs(),
    gmp: getGMPStructs(),
    versionControl: getVersionControlStructs(),
    gasService: getGasServiceStructs(),
    its: getITSStructs(),
    relayerDiscovery: getRelayerDiscoveryStructs(),
};
