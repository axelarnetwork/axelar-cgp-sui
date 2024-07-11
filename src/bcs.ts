import { bcs } from '@mysten/sui.js/bcs';

function getAxelarStructs() {
    const Bytes32 = bcs.Address;

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
    };
}

function getSquidStructs() {
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

    return {
        DeepbookV2SwapData,
        SuiTransferSwapData,
        ItsTransferSwapData,
    };
}

export const bcsStructs = {
    gateway: getAxelarStructs(),
    squid: getSquidStructs(),
};
