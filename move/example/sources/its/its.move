module example::its {
    use axelar_gateway::{channel::{Self, ApprovedMessage, Channel}, gateway::{Self, Gateway}, message_ticket::MessageTicket};
    use example::utils::concat;
    use gas_service::gas_service::GasService;
    use interchain_token_service::{
        coin_management,
        discovery as its_discovery,
        interchain_token_service::{Self, InterchainTokenService},
        token_id::TokenId
    };
    use relayer_discovery::{discovery::RelayerDiscovery, transaction::{Self, Transaction}};
    use std::{ascii::{Self, String}, type_name};
    use sui::{address, clock::Clock, coin::{CoinMetadata, Coin, TreasuryCap}, event, hex, sui::SUI};

    // -------
    // Structs
    // -------
    public struct Singleton has key {
        id: UID,
        channel: Channel,
    }

    public struct ExecutedWithToken has copy, drop {
        source_chain: String,
        source_address: vector<u8>,
        data: vector<u8>,
        amount: u64,
    }

    /// -----
    /// Setup
    /// -----
    fun init(ctx: &mut TxContext) {
        let singletonId = object::new(ctx);
        let channel = channel::new(ctx);
        transfer::share_object(Singleton {
            id: singletonId,
            channel,
        });
    }

    // -----
    // Public Functions
    // -----

    /// This needs to be called to register the transaction so that the relayer
    /// knows to call this to fulfill calls.
    public fun register_transaction(discovery: &mut RelayerDiscovery, singleton: &Singleton, its: &InterchainTokenService, clock: &Clock) {
        let arguments = vector[
            concat(vector[0u8], object::id_address(singleton).to_bytes()),
            concat(vector[0u8], object::id_address(its).to_bytes()),
            vector[3u8],
            concat(vector[0u8], object::id_address(clock).to_bytes()),
        ];

        let transaction = transaction::new_transaction(
            false,
            vector[
                transaction::new_move_call(
                    transaction::new_function(
                        address::from_bytes(
                            hex::decode(
                                *ascii::as_bytes(
                                    &type_name::address_string(
                                        &type_name::with_defining_ids<Singleton>(),
                                    ),
                                ),
                            ),
                        ),
                        ascii::string(b"its"),
                        ascii::string(b"get_final_transaction"),
                    ),
                    arguments,
                    vector[],
                ),
            ],
        );

        discovery.register_transaction(&singleton.channel, transaction);
    }

    public fun get_final_transaction(singleton: &Singleton, its: &InterchainTokenService, payload: vector<u8>, clock: &Clock): Transaction {
        let arguments = vector[
            vector[2u8],
            concat(vector[0u8], object::id_address(singleton).to_bytes()),
            concat(vector[0u8], object::id_address(its).to_bytes()),
            concat(vector[0u8], object::id_address(clock).to_bytes()),
        ];

        // Get the coin type from its
        let (token_id, _, _, _) = its_discovery::interchain_transfer_info(
            payload,
        );
        let coin_type = (*its.registered_coin_type(token_id)).into_string();

        let transaction = transaction::new_transaction(
            true,
            vector[
                transaction::new_move_call(
                    transaction::new_function(
                        address::from_bytes(
                            hex::decode(
                                *ascii::as_bytes(
                                    &type_name::address_string(
                                        &type_name::with_defining_ids<Singleton>(),
                                    ),
                                ),
                            ),
                        ),
                        ascii::string(b"its"),
                        ascii::string(b"receive_interchain_transfer"),
                    ),
                    arguments,
                    vector[coin_type],
                ),
            ],
        );

        transaction
    }

    /// This function needs to be called first to register the coin for either of
    /// the other two functions to work.
    public fun register_coin<TOKEN>(its: &mut InterchainTokenService, coin_metadata: &CoinMetadata<TOKEN>): TokenId {
        let coin_management = coin_management::new_locked();

        its.register_coin_from_metadata(
            coin_metadata,
            coin_management,
        )
    }

    /// Registers a coin with the Interchain Token Service (ITS), using the provided `TreasuryCap` to manage the coin.
    /// The `TreasuryCap` gives the ITS control over minting and burning of this coin.
    public fun register_coin_with_cap<TOKEN>(
        its: &mut InterchainTokenService,
        coin_metadata: &CoinMetadata<TOKEN>,
        treasury_cap: TreasuryCap<TOKEN>,
    ): TokenId {
        let coin_management = coin_management::new_with_cap(treasury_cap);

        its.register_coin_from_metadata(
            coin_metadata,
            coin_management,
        )
    }

    public fun deploy_remote_interchain_token<TOKEN>(
        its: &mut InterchainTokenService,
        gateway: &mut Gateway,
        gas_service: &mut GasService,
        destination_chain: String,
        token_id: TokenId,
        gas: Coin<SUI>,
        gas_params: vector<u8>,
        refund_address: address,
    ) {
        let message_ticket = its.deploy_remote_interchain_token<TOKEN>(
            token_id,
            destination_chain,
        );

        pay_gas_and_send_message(
            gateway,
            gas_service,
            gas,
            message_ticket,
            refund_address,
            gas_params,
        );
    }

    /// This should trigger an interchain transfer.
    public fun send_interchain_transfer_call<TOKEN>(
        singleton: &Singleton,
        its: &mut InterchainTokenService,
        gateway: &mut Gateway,
        gas_service: &mut GasService,
        token_id: TokenId,
        coin: Coin<TOKEN>,
        destination_chain: String,
        destination_address: vector<u8>,
        metadata: vector<u8>,
        refund_address: address,
        gas: Coin<SUI>,
        gas_params: vector<u8>,
        clock: &Clock,
    ) {
        let interchain_transfer_ticket = interchain_token_service::prepare_interchain_transfer<TOKEN>(
            token_id,
            coin,
            destination_chain,
            destination_address,
            metadata,
            &singleton.channel,
        );

        let message_ticket = its.send_interchain_transfer<TOKEN>(
            interchain_transfer_ticket,
            clock,
        );

        pay_gas_and_send_message(
            gateway,
            gas_service,
            gas,
            message_ticket,
            refund_address,
            gas_params,
        );
    }

    /// This should receive some coins, give them to the executor, and emit and
    /// event with all the relevant info.
    #[allow(lint(self_transfer))]
    public fun receive_interchain_transfer<TOKEN>(
        approved_message: ApprovedMessage,
        singleton: &Singleton,
        its: &mut InterchainTokenService,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let (source_chain, source_address, data, coin) = its.receive_interchain_transfer_with_data<TOKEN>(
            approved_message,
            &singleton.channel,
            clock,
            ctx,
        );

        event::emit(ExecutedWithToken {
            source_chain,
            source_address,
            data,
            amount: coin.value(),
        });

        // give the coin to the caller
        transfer::public_transfer(coin, ctx.sender());
    }

    // -----
    // Internal Functions
    // -----
    fun pay_gas_and_send_message(
        gateway: &Gateway,
        gas_service: &mut GasService,
        gas: Coin<SUI>,
        message_ticket: MessageTicket,
        refund_address: address,
        gas_params: vector<u8>,
    ) {
        gas_service.pay_gas(
            &message_ticket,
            gas,
            refund_address,
            gas_params,
        );

        gateway::send_message(gateway, message_ticket);
    }
}
