import { bcs } from '@mysten/sui/bcs';
import { UID } from './types';

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

    const GatewayV0 = bcs.struct('GatewayV0', {
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

    const DeepbookV2SwapData = bcs.struct('DeepbookV2SwapData', {
        swap_type: bcs.U8,
        pool_id: bcs.Address,
        has_base: bcs.Bool,
        min_output: bcs.U64,
        base_type: bcs.String,
        quote_type: bcs.String,
        lot_size: bcs.U64,
        should_sweep: bcs.Bool,
    });

    const SuiTransferSwapData = bcs.struct('SuiTransferSwapData', {
        swap_type: bcs.U8,
        coin_type: bcs.String,
        recipient: bcs.Address,
    });

    const ItsTransferSwapData = bcs.struct('ItsTransferSwapData', {
        swap_type: bcs.U8,
        coin_type: bcs.String,
        token_id: bcs.Address,
        destination_chain: bcs.String,
        destination_address: bcs.vector(bcs.U8),
        metadata: bcs.vector(bcs.U8),
    });

    const Squid = bcs.struct('Squid', {
        id: UID,
        channel: Channel,
        coin_bag: CoinBag,
    });

    return {
        DeepbookV2SwapData,
        SuiTransferSwapData,
        ItsTransferSwapData,
        Squid,
    };
}

function getRelayerDiscoveryStructs() {
    const { Table } = getCommonStructs();
    const { VersionControl } = getVersionControlStructs();

    const RelayerDiscoveryV0 = bcs.struct('RelayerDiscoveryV0', {
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

    const ITSV0 = bcs.struct('ITSV0', {
        channel: Channel,
        address_tracker: InterchainAddressTracker,
        unregistered_coin_types: Table,
        unregistered_coins: Bag,
        registered_coin_types: Table,
        registered_coins: Bag,
        relayer_discovery_id: bcs.Address,
        version_control: VersionControl,
    });

    const ITS = bcs.struct('ITS', {
        id: UID,
        name: bcs.u64(),
        value: ITSV0,
    });

    return {
        InterchainAddressTracker,
        ITS,
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

    const GasServiceV0 = bcs.struct('GasServiceV0', {
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
