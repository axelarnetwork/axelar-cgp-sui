module interchain_token_service::events {
    use axelar_gateway::{bytes32::{Self, Bytes32}, channel::Channel};
    use interchain_token_service::{token_id::{TokenId, UnregisteredTokenId, UnlinkedTokenId}, token_manager_type::TokenManagerType};
    use std::{ascii::String, string};
    use sui::{address, event, hash::keccak256};

    // -----
    // Types
    // -----
    public struct CoinRegistered<phantom T> has copy, drop {
        token_id: TokenId,
    }

    public struct InterchainTransfer<phantom T> has copy, drop {
        token_id: TokenId,
        source_address: address,
        destination_chain: String,
        destination_address: vector<u8>,
        amount: u64,
        data_hash: Bytes32,
    }

    public struct InterchainTokenDeploymentStarted<phantom T> has copy, drop {
        token_id: TokenId,
        name: string::String,
        symbol: String,
        decimals: u8,
        destination_chain: String,
    }

    public struct InterchainTransferReceived<phantom T> has copy, drop {
        message_id: String,
        token_id: TokenId,
        source_chain: String,
        source_address: vector<u8>,
        destination_address: address,
        amount: u64,
        data_hash: Bytes32,
    }

    public struct UnregisteredCoinReceived<phantom T> has copy, drop {
        token_id: UnregisteredTokenId,
        symbol: String,
        decimals: u8,
    }

    public struct UnlinkedCoinReceived<phantom T> has copy, drop {
        unlinked_token_id: UnlinkedTokenId,
        token_id: TokenId,
        token_manager_type: TokenManagerType,
    }

    public struct UnlinkedCoinRemoved<phantom T> has copy, drop {
        unlinked_token_id: UnlinkedTokenId,
        token_id: TokenId,
        token_manager_type: TokenManagerType,
    }

    public struct TrustedChainAdded has copy, drop {
        chain_name: String,
    }

    public struct TrustedChainRemoved has copy, drop {
        chain_name: String,
    }

    public struct FlowLimitSet<phantom T> has copy, drop {
        token_id: TokenId,
        flow_limit: Option<u64>,
    }

    public struct DistributorshipTransfered<phantom T> has copy, drop {
        token_id: TokenId,
        new_distributor: Option<address>,
    }

    public struct OperatorshipTransfered<phantom T> has copy, drop {
        token_id: TokenId,
        new_operator: Option<address>,
    }

    public struct InterchainTokenIdClaimed<phantom T> has copy, drop {
        token_id: TokenId,
        deployer: ID,
        salt: Bytes32,
    }

    public struct LinkTokenStarted has copy, drop {
        token_id: TokenId,
        destination_chain: String,
        source_token_address: vector<u8>,
        destination_token_address: vector<u8>,
        token_manager_type: TokenManagerType,
        link_params: vector<u8>,
    }

    public struct LinkTokenReceived<phantom T> has copy, drop {
        token_id: TokenId,
        source_chain: String,
        source_token_address: vector<u8>,
        token_manager_type: TokenManagerType,
        link_params: vector<u8>,
    }

    public struct CoinMetadataRegistered<phantom T> has copy, drop {
        decimals: u8,
    }

    // -----------------
    // Package Functions
    // -----------------
    public(package) fun coin_registered<T>(token_id: TokenId) {
        event::emit(CoinRegistered<T> {
            token_id,
        });
    }

    public(package) fun interchain_transfer<T>(
        token_id: TokenId,
        source_address: address,
        destination_chain: String,
        destination_address: vector<u8>,
        amount: u64,
        data: &vector<u8>,
    ) {
        let data_hash = if (data.length() == 0) {
            bytes32::new(@0x0)
        } else {
            bytes32::new(address::from_bytes(keccak256(data)))
        };
        event::emit(InterchainTransfer<T> {
            token_id,
            source_address,
            destination_chain,
            destination_address,
            amount,
            data_hash,
        });
    }

    public(package) fun interchain_token_deployment_started<T>(
        token_id: TokenId,
        name: string::String,
        symbol: String,
        decimals: u8,
        destination_chain: String,
    ) {
        event::emit(InterchainTokenDeploymentStarted<T> {
            token_id,
            name,
            symbol,
            decimals,
            destination_chain,
        });
    }

    public(package) fun interchain_transfer_received<T>(
        message_id: String,
        token_id: TokenId,
        source_chain: String,
        source_address: vector<u8>,
        destination_address: address,
        amount: u64,
        data: &vector<u8>,
    ) {
        let data_hash = bytes32::new(address::from_bytes(keccak256(data)));
        event::emit(InterchainTransferReceived<T> {
            message_id,
            token_id,
            source_chain,
            source_address,
            destination_address,
            amount,
            data_hash,
        });
    }

    public(package) fun unregistered_coin_received<T>(token_id: UnregisteredTokenId, symbol: String, decimals: u8) {
        event::emit(UnregisteredCoinReceived<T> {
            token_id,
            symbol,
            decimals,
        });
    }

    public(package) fun unlinked_coin_received<T>(
        unlinked_token_id: UnlinkedTokenId,
        token_id: TokenId,
        token_manager_type: TokenManagerType,
    ) {
        event::emit(UnlinkedCoinReceived<T> {
            unlinked_token_id,
            token_id,
            token_manager_type,
        });
    }

    public(package) fun unlinked_coin_removed<T>(
        unlinked_token_id: UnlinkedTokenId,
        token_id: TokenId,
        token_manager_type: TokenManagerType,
    ) {
        event::emit(UnlinkedCoinRemoved<T> {
            unlinked_token_id,
            token_id,
            token_manager_type,
        });
    }

    public(package) fun trusted_chain_added(chain_name: String) {
        event::emit(TrustedChainAdded {
            chain_name,
        });
    }

    public(package) fun trusted_chain_removed(chain_name: String) {
        event::emit(TrustedChainRemoved {
            chain_name,
        });
    }

    public(package) fun flow_limit_set<T>(token_id: TokenId, flow_limit: Option<u64>) {
        event::emit(FlowLimitSet<T> {
            token_id,
            flow_limit,
        });
    }

    public(package) fun distributorship_transfered<T>(token_id: TokenId, new_distributor: Option<address>) {
        event::emit(DistributorshipTransfered<T> {
            token_id,
            new_distributor,
        });
    }

    public(package) fun operatorship_transfered<T>(token_id: TokenId, new_operator: Option<address>) {
        event::emit(OperatorshipTransfered<T> {
            token_id,
            new_operator,
        });
    }

    public(package) fun interchain_token_id_claimed<T>(token_id: TokenId, deployer: &Channel, salt: Bytes32) {
        event::emit(InterchainTokenIdClaimed<T> {
            token_id,
            deployer: deployer.id(),
            salt,
        });
    }

    public(package) fun link_token_started(
        token_id: TokenId,
        destination_chain: String,
        source_token_address: vector<u8>,
        destination_token_address: vector<u8>,
        token_manager_type: TokenManagerType,
        link_params: vector<u8>,
    ) {
        event::emit(LinkTokenStarted {
            token_id,
            destination_chain,
            source_token_address,
            destination_token_address,
            token_manager_type,
            link_params,
        });
    }

    public(package) fun coin_metadata_registered<T>(decimals: u8) {
        event::emit(CoinMetadataRegistered<T> {
            decimals,
        });
    }

    public(package) fun link_token_received<T>(
        token_id: TokenId,
        source_chain: String,
        source_token_address: vector<u8>,
        token_manager_type: TokenManagerType,
        link_params: vector<u8>,
    ) {
        event::emit(LinkTokenReceived<T> {
            token_id,
            source_chain,
            source_token_address,
            token_manager_type,
            link_params,
        });
    }

    // ---------
    // Test Only
    // ---------
    #[test_only]
    use interchain_token_service::coin::COIN;
    #[test_only]
    use interchain_token_service::token_id;
    #[test_only]
    use utils::utils;

    // -----
    // Tests
    // -----
    #[test]
    fun test_interchain_transfer_empty_data() {
        let token_id = token_id::from_address(@0x1);
        let source_address = @0x2;
        let destination_chain = b"destination chain".to_ascii_string();
        let destination_address = b"destination address";
        let amount = 123;
        let data = b"";
        let data_hash = bytes32::new(@0x0);

        interchain_transfer<COIN>(
            token_id,
            source_address,
            destination_chain,
            destination_address,
            amount,
            &data,
        );
        let event = utils::assert_event<InterchainTransfer<COIN>>();

        assert!(event.data_hash == data_hash);
        assert!(event.source_address == source_address);
        assert!(event.destination_chain == destination_chain);
        assert!(event.destination_address == destination_address);
        assert!(event.amount == amount);
    }

    #[test]
    fun test_interchain_transfer_nonempty_data() {
        let token_id = token_id::from_address(@0x1);
        let source_address = @0x2;
        let destination_chain = b"destination chain".to_ascii_string();
        let destination_address = b"destination address";
        let amount = 123;
        let data = b"data";
        let data_hash = bytes32::new(address::from_bytes(keccak256(&data)));

        interchain_transfer<COIN>(
            token_id,
            source_address,
            destination_chain,
            destination_address,
            amount,
            &data,
        );
        let event = utils::assert_event<InterchainTransfer<COIN>>();

        assert!(event.data_hash == data_hash);
        assert!(event.source_address == source_address);
        assert!(event.destination_chain == destination_chain);
        assert!(event.destination_address == destination_address);
        assert!(event.amount == amount);
    }
}
