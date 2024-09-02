import { fromHEX, toHEX } from '@mysten/bcs';
import { bcs } from '@mysten/sui/bcs';
import { UID } from './types';

function getCommonStructs() {
    const Bytes32 = bcs.fixedArray(32, bcs.u8()).transform({
        input: (id: string) => fromHEX(id),
        output: (id) => toHEX(Uint8Array.from(id)),
    });

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

function getAxelarStructs() {
    const { Bytes32, Bag } = getCommonStructs();

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

function getITSStructs() {
    const { Table, Bag, Channel } = getCommonStructs();

    const InterchainAddressTracker = bcs.struct('InterchainAddressTracker', {
        trusted_addresses: Table,
    });

    const ITS = bcs.struct('ITS', {
        id: UID,
        channel: Channel,
        address_tracker: InterchainAddressTracker,
        unregistered_coin_types: Table,
        unregistered_coin_info: Bag,
        registered_coin_types: Table,
        registered_coins: Bag,
    });

    return {
        InterchainAddressTracker,
        ITS,
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
    const GasService = bcs.struct('GasService', {
        id: UID,
        balance: bcs.U64,
    });

    return {
        GasService,
    };
}

export const bcsStructs = {
    common: getCommonStructs(),
    gateway: getAxelarStructs(),
    squid: getSquidStructs(),
    gmp: getGMPStructs(),
    gasService: getGasServiceStructs(),
    its: getITSStructs(),
};
