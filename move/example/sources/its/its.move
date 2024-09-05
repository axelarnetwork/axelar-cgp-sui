module example::its_example {
    use std::ascii;
    use std::ascii::{String};
    use std::type_name;

    use sui::event;
    use sui::address;
    use sui::hex;
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::clock::Clock;
    use sui::url::Url;

    use axelar_gateway::channel::{Self, Channel, ApprovedMessage};
    use axelar_gateway::discovery::{Self, RelayerDiscovery, Transaction};

    use its::service;
    use its::its::ITS;
    use its::token_id::TokenId;
    use its::coin_management;
    use its::coin_info;

    public struct ITS_EXAMPLE has drop {}

    public struct Singleton has key {
        id: UID,
        channel: Channel,
        treasury_cap: Option<TreasuryCap<ITS_EXAMPLE>>,
        coin_metadata: Option<CoinMetadata<ITS_EXAMPLE>>,
        token_id: Option<TokenId>,
    }

    public struct Executed has copy, drop {
        source_chain: String,
        source_address: vector<u8>,
        data: vector<u8>,
        amount: u64,
    }

    fun init(witness: ITS_EXAMPLE, ctx: &mut TxContext) {
        let decimals: u8 = 8;
        let symbol: vector<u8> = b"ITS";
        let name: vector<u8> = b"Test Coin";
        let description = b"";
        let icon_url = option::none<Url>();
        let (treasury_cap, coin_metadata) = coin::create_currency<ITS_EXAMPLE>(
            witness,
            decimals,
            symbol,
            name,
            description,
            icon_url,
            ctx,
        );

        let singletonId = object::new(ctx);
        let channel = channel::new(ctx);
        transfer::share_object(Singleton {
            id: singletonId,
            channel,
            treasury_cap: option::some(treasury_cap),
            coin_metadata: option::some(coin_metadata),
            token_id: option::none<TokenId>(),
        });
    }

    public fun token_id(self: &Singleton): &TokenId {
        self.token_id.borrow()
    }

    public fun mint(self: &mut Singleton, amount: u64, ctx: &mut TxContext): Coin<ITS_EXAMPLE> {
        self.treasury_cap.borrow_mut().mint(amount, ctx)
    }

    public fun register_transaction(discovery: &mut RelayerDiscovery, singleton: &Singleton, its: &ITS) {
        let mut arguments = vector::empty<vector<u8>>();

        // Singleton object
        let mut arg = vector::singleton<u8>(0);
        arg.append(object::id_address(singleton).to_bytes());
        arguments.push_back(arg);

        // ITS object
        arg = vector::singleton<u8>(0);
        arg.append(object::id_address(its).to_bytes());
        arguments.push_back(arg);

        // payload
        arg = vector[ 3 ];
        arguments.push_back(arg);

        let transaction = discovery::new_transaction(
            true,
            vector[
                discovery::new_move_call(
                    discovery::new_function(
                        address::from_bytes(hex::decode(*ascii::as_bytes(&type_name::get_address(&type_name::get<Singleton>())))),
                        ascii::string(b"its"),
                        ascii::string(b"get_transaction")
                    ),
                    arguments,
                    vector[],
                )
            ]
        );

        discovery::register_transaction(discovery, &singleton.channel, transaction);
    }

    public fun get_transaction(singleton: &Singleton, its: &ITS, payload: vector<u8>): Transaction {
        let mut arguments = vector::empty<vector<u8>>();

        // ApprovedMessage
        let mut arg = vector::singleton<u8>(2);
        arguments.push_back(arg);


        // Singleton object
        arg = vector::singleton<u8>(0);
        arg.append(object::id_address(singleton).to_bytes());
        arguments.push_back(arg);

        // ITS object
        arg = vector::singleton<u8>(0);
        arg.append(object::id_address(its).to_bytes());
        arguments.push_back(arg);
        
        // ITS object
        arg = vector::singleton<u8>(0);
        arg.append(@0x6.to_bytes());
        arguments.push_back(arg);

        let (token_id, _, _, _) = its::discovery::get_interchain_transfer_info(payload);
        let coin_type = its.get_registered_coin_type(token_id);

        discovery::new_transaction(
            true,
            vector[
                discovery::new_move_call(
                    discovery::new_function(
                        address::from_bytes(hex::decode(*ascii::as_bytes(&type_name::get_address(&type_name::get<Singleton>())))),
                        ascii::string(b"its"),
                        ascii::string(b"execute_interchain_transfer")
                    ),
                    arguments,
                    vector[(*coin_type).into_string()],
                )
            ]
        )
    }

    public fun register_coin(self: &mut Singleton, its: &mut ITS) {
        let coin_info = coin_info::from_metadata(self.coin_metadata.extract(), 12);
        let coin_management = coin_management::new_with_cap(self.treasury_cap.extract());
        
        let token_id = service::register_coin(its, coin_info, coin_management);

        self.token_id.fill(token_id);
    }

    public fun send_interchain_transfer(
        self: &Singleton, 
        its: &mut ITS,
        destination_chain: String, 
        destination_address: vector<u8>, 
        coin: Coin<ITS_EXAMPLE>,
        metadata: vector<u8>,
        clock: &Clock,
    ) {
        let token_id = *self.token_id.borrow();
        service::interchain_transfer<ITS_EXAMPLE>(
            its,
            token_id,
            coin,
            destination_chain,
            destination_address,
            metadata,
            &self.channel,
            clock,
        );
    }

    public fun execute_interchain_transfer(
        approved_message: ApprovedMessage, 
        singleton: &mut Singleton, 
        its: &mut ITS, 
        clock: &Clock, 
        ctx: &mut TxContext
    ): Coin<ITS_EXAMPLE> {
        let (
            source_chain,
            source_address,
            data,
            coin,
        ) = service::receive_interchain_transfer_with_data<ITS_EXAMPLE>(
            its,
            approved_message,
            &singleton.channel,
            clock,
            ctx,
        );

        event::emit(Executed { 
            source_chain,
            source_address,
            data,
            amount: coin.value(),
        });

        coin
    }
  }
