require('dotenv').config();
const { publishInterchainToken } = require("./its/publish-interchain-token");
const { parseEnv, setConfig, getConfig } = require("./utils");
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { SuiClient } = require('@mysten/sui.js/client');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { publishPackageFull, publishPackage } = require('./publish-package');
const { registerInterchainToken } = require('./its/register-token');
const { bcs } = require('@mysten/bcs');
const {
    utils: { arrayify },
} = require('ethers');
const { hexlify, defaultAbiCoder } = require('ethers/lib/utils');
const { receiveCall } = require('./test-receive-call');
const { setItsDiscovery } = require('./its/discovery');
const { setTrustedAddresses } = require('./its/set-trusted-address');

const deepbook = '0xdee9';


const tickSize = 1e6;
const lotSize = 1e3;
const amountBase = 1e6*1e9;
const amountQuote = amountBase;
const amount = lotSize*1000000;
const sourceChain = 'sourceAddress';
const sourceAddress = 'trustedITsAddress';

const DEEPBOOK_SWAP_TYPE = 1;
const SWEEP_SWAP_TYPE = 0;

const MESSAGE_TYPE_INTERCHAIN_TRANSFER = 0;

async function sleep(ms = 100) {
    await new Promise((resolve) => {
        setTimeout(resolve, ms);
    })
}

async function placeLimitOrder(client, keypair, env, isBid, price, amount) {
    const {
        pool,
        accountCap,
        base,
        quote,
    } = getConfig('trading', env.alias);


    const tx = new TransactionBlock();
    if(isBid) {
        const coin = tx.moveCall({
            target: `0x2::coin::split`,
            arguments: [tx.object(quote.objectId), tx.pure(Math.floor(amount * price / 1e9))],
            typeArguments: [quote.type],
        });
       
        tx.moveCall({
            target: `0xdee9::clob_v2::deposit_quote`,
            arguments: [
                tx.object(pool),
                coin,
                tx.object(accountCap),
            ],
            typeArguments: [base.type, quote.type],
        });
    } else {
        const coin = tx.moveCall({
            target: `0x2::coin::split`,
            arguments: [tx.object(base.objectId), tx.pure(amount)],
            typeArguments: [base.type],
        });
       
        tx.moveCall({
            target: `0xdee9::clob_v2::deposit_base`,
            arguments: [
                tx.object(pool),
                coin,
                tx.object(accountCap),
            ],
            typeArguments: [base.type, quote.type],
        });
    }


    tx.moveCall({
        target: `0xdee9::clob_v2::place_limit_order`,
        arguments: [
            tx.object(pool),
            tx.pure(0),
            tx.pure(price),
            tx.pure(amount),
            tx.pure(0),
            tx.pure(isBid),
            tx.pure(10000000000000000000),
            tx.pure(3),
            tx.object('0x6'),
            tx.object(accountCap),
        ],
        typeArguments: [base.type, quote.type],
    });

    await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForEffectsCert',
    });
}

async function prepare(client, keypair, env) {
    const address = keypair.getPublicKey().toSuiAddress();
    try {
        await requestSuiFromFaucetV0({
        // use getFaucetHost to make sure you're using correct faucet address
        // you can also just use the address (see Sui Typescript SDK Quick Start for values)
        host: getFaucetHost(env.alias),
        recipient: address,
        });
    } catch (e) {
        console.log(e);
    }
    
    //await publishPackageFull('trading', client, keypair, env);

    //const config = getConfig('trading', env.alias);
    
    const [baseId, baseType, baseCoin]  = await registerInterchainToken(
        client,
        keypair,
        getConfig('its', env.alias),
        'Base',
        'B',
        9,
        amountBase,
    )

    const [quoteId, quoteType, quoteCoin] = await registerInterchainToken(
        client,
        keypair,
        getConfig('its', env.alias),
        'Quote',
        'Q',
        9,
        amountQuote,
    );

    let tx = new TransactionBlock();

    const creationFee = tx.splitCoins(
        tx.gas,
        [tx.pure(100*1e9)],
    );

    tx.moveCall({
        target: `${deepbook}::clob_v2::create_pool`,
        arguments: [
            tx.pure(tickSize),
            tx.pure(lotSize),
            creationFee,
        ],
        typeArguments: [baseType, quoteType],
    });

    let account = tx.moveCall({
        target: `${deepbook}::clob_v2::create_account`,
        arguments: [],
        typeArguments: [],
    });    

    tx.moveCall({
        target: `0x2::transfer::public_transfer`,
        arguments: [account, tx.pure(keypair.toSuiAddress())],
        typeArguments: ['0xdee9::custodian_v2::AccountCap'],
    });

    let result = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForEffectsCert',
    }); 
    
    const pool = result.objectChanges.find(object => object.objectType.startsWith('0xdee9::clob_v2::Pool<')).objectId;
    const poolCap = result.objectChanges.find(object => object.objectType.startsWith('0xdee9::clob_v2::PoolOwnerCap')).objectId;
    const accountCap = result.objectChanges.find(object => object.objectType.startsWith('0xdee9::custodian_v2::AccountCap')).objectId;
    const suiCoin = result.objectChanges.find(object => object.objectType.startsWith('0x2::coin::Coin<')).objectId;

    setConfig('trading', env.alias, {
        pool,
        accountCap,
        base: {
            type: baseType,
            tokenId: baseId,
            objectId: baseCoin,
        },
        quote: {
            type: quoteType,
            tokenId: quoteId,
            objectId: quoteCoin,
        },
        suiCoin,
    });

    await placeLimitOrder(client, keypair, env, false, 1100e6, amountQuote);
    await sleep(300);
    await placeLimitOrder(client, keypair, env, true, 990e6, amountBase);
    await sleep(300);

    await setItsDiscovery(client, keypair, env.alias);
    await sleep(300);
    await setTrustedAddresses(client, keypair, env.alias, [sourceChain], [sourceAddress]);

    await publishPackageFull('squid', client, keypair, env);
}

async function placeLimitOrders(client, keypair, env, isBid, n = 10) {
    if(isBid) {
        for(let i=0; i<n; i++) {console.log(i);
            const price = 1e9 - tickSize * Math.floor(1 + Math.random() * 10);
            const amount = 1e9 * Math.floor(100 + Math.random() * 100);
            try {
                await placeLimitOrder(client, keypair, env, true, price, amount);
            } catch(e) {
                console.log(e);
                i--;
            }
    
        }
    } else {
        for(let i=0; i<n; i++) {console.log(i);
            const price = 1e9 + tickSize * Math.floor(1 + Math.random() * 10);
            const amount = 1e9 * Math.floor(100 + Math.random() * 100);
            try {
                await placeLimitOrder(client, keypair, env, false, price, amount);
            } catch(e) {
                console.log(e);
                i--;
            }
    
        }
    }

}


async function testBaseForQuote(client, keypair, env) {
    //await placeLimitOrders(client, keypair, env, true, 10);

    const {
        pool,
        base,
        quote,
    } = getConfig('trading', env.alias);

    const { packageId } = await publishPackage('trading', client, keypair);
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${packageId}::trading::predict_base_for_quote`,
        arguments: [
            tx.object(pool),
            tx.pure(amount),
            tx.pure(lotSize),
            tx.object('0x6'),

        ],
        typeArguments: [base.type, quote.type],
    });
    
    const coin = tx.moveCall({
        target: `0x2::coin::split`,
        arguments: [tx.object(base.objectId), tx.pure(amount)],
        typeArguments: [base.type],
    });

    const accountCap = tx.moveCall({
        target: `${deepbook}::clob_v2::create_account`,
        arguments: [],
        typeArguments: [],
    });

    const [leftover_base, leftover_quote] = tx.moveCall({
        target: `${deepbook}::clob_v2::swap_exact_base_for_quote`,
        arguments: [
            tx.object(pool), 
            tx.pure(0),
            accountCap,
            tx.pure(amount),
            coin,
            tx.moveCall({target: '0x2::coin::zero', typeArguments: [quote.type]}),
            tx.object('0x6'),
        ],
        typeArguments: [base.type, quote.type],
    });

    tx.moveCall({
        target: `${deepbook}::custodian_v2::delete_account_cap`,
        arguments: [accountCap],
        typeArguments: [],
    });

    tx.moveCall({
        target: `0x2::transfer::public_transfer`,
        arguments: [leftover_base, tx.pure(keypair.toSuiAddress())],
        typeArguments: [`0x2::coin::Coin<${base.type}>`],
    });
    tx.moveCall({
        target: `0x2::transfer::public_transfer`,
        arguments: [leftover_quote, tx.pure(keypair.toSuiAddress())],
        typeArguments: [`0x2::coin::Coin<${quote.type}>`],
    });

    const result = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForEffectsCert',
    });

    const response = await client.queryEvents({
        query: {
            MoveEventType: `${packageId}::trading::Event`,
        },
    });
    console.log(response.data.map(event => event.parsedJson));

    const quoteCoinId = result.objectChanges.find(change => change.objectType == `0x2::coin::Coin<${quote.type}>`).objectId;
    const quoteCoin = await client.getObject({
        id: quoteCoinId,
        options: {
            showContent: true,
        }
    });

    const baseCoinId = result.objectChanges.find(change => change.objectType == `0x2::coin::Coin<${base.type}>` && change.type === 'created').objectId;
    const baseCoin = await client.getObject({
        id: baseCoinId,
        options: {
            showContent: true,
        }
    });

    console.log({
        amount_left: baseCoin.data.content.fields.balance,
        output: quoteCoin.data.content.fields.balance,
    });
}

async function testQuoteForBase(client, keypair, env) {
    await placeLimitOrders(client, keypair, env, false, 10);

    const {
        pool,
        base,
        quote,
    } = getConfig('trading', env.alias);

    const { packageId } = await publishPackage('trading', client, keypair);
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${packageId}::trading::predict_quote_for_base`,
        arguments: [
            tx.object(pool),
            tx.pure(amount),
            tx.pure(lotSize),
            tx.object('0x6'),

        ],
        typeArguments: [base.type, quote.type],
    });
    
    const coin = tx.moveCall({
        target: `0x2::coin::split`,
        arguments: [tx.object(quote.objectId), tx.pure(amount)],
        typeArguments: [quote.type],
    });

    const accountCap = tx.moveCall({
        target: `${deepbook}::clob_v2::create_account`,
        arguments: [],
        typeArguments: [],
    });

    const [leftover_base, leftover_quote] = tx.moveCall({
        target: `${deepbook}::clob_v2::swap_exact_quote_for_base`,
        arguments: [
            tx.object(pool), 
            tx.pure(0),
            accountCap,
            tx.pure(amount),
            tx.object('0x6'),
            coin,
        ],
        typeArguments: [base.type, quote.type],
    });

    tx.moveCall({
        target: `${deepbook}::custodian_v2::delete_account_cap`,
        arguments: [accountCap],
        typeArguments: [],
    });

    tx.moveCall({
        target: `0x2::transfer::public_transfer`,
        arguments: [leftover_base, tx.pure(keypair.toSuiAddress())],
        typeArguments: [`0x2::coin::Coin<${base.type}>`],
    });
    tx.moveCall({
        target: `0x2::transfer::public_transfer`,
        arguments: [leftover_quote, tx.pure(keypair.toSuiAddress())],
        typeArguments: [`0x2::coin::Coin<${quote.type}>`],
    });

    const result = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForEffectsCert',
    });

    const response = await client.queryEvents({
        query: {
            MoveEventType: `${packageId}::trading::Event`,
        },
    });
    console.log(response.data.map(event => event.parsedJson));

    const quoteCoinId = result.objectChanges.find(change => change.objectType == `0x2::coin::Coin<${quote.type}>` && change.type === 'created').objectId;
    const quoteCoin = await client.getObject({
        id: quoteCoinId,
        options: {
            showContent: true,
        }
    });

    const baseCoinId = result.objectChanges.find(change => change.objectType == `0x2::coin::Coin<${base.type}>` && change.type === 'created').objectId;
    const baseCoin = await client.getObject({
        id: baseCoinId,
        options: {
            showContent: true,
        }
    });

    console.log({
        amount_left: quoteCoin.data.content.fields.balance,
        output: baseCoin.data.content.fields.balance,
    });
}

async function test(client, keypair, env) {
    const address = bcs.fixedArray(32, bcs.u8()).transform({
        input: (id) => arrayify(id),
        output: (id) => hexlify(id),
    });

    const squid_info = getConfig('squid', env.alias);
    const {pool, base, quote} = getConfig('trading', env.alias);
    const its_info = getConfig('its', env.alias);

    const swapInfoStruct = bcs.struct('SwapInfo', {
        swap_data: bcs.vector(bcs.vector(bcs.u8())),
        type_in: bcs.string(),
        destination_in: bcs.vector(bcs.u8()),
        type_out: bcs.string(),
        destination_out: bcs.vector(bcs.u8()),
    });

    const deepbookSwapStruct = bcs.struct('DeepbookSwap', {
        swap_type: bcs.u8(),
        pool_id: address,
        has_base: bcs.bool(),
        min_out: bcs.u64(),
        base_type: bcs.string(),
        quote_type: bcs.string(),
        lot_size: bcs.u64(),
    });

    const sweepStruct = bcs.struct('DeepbookSwap', {
        swap_type: bcs.u8(),
        type: bcs.string(),
    });

    const destination = bcs.struct('DestinationLocal', {
        to_sui: bcs.bool(),
        address: address,
    }).serialize({
        to_sui: true,
        address: keypair.toSuiAddress(),
    }).toBytes();
    
    const swapInfoData = swapInfoStruct.serialize({
        swap_data: [
            deepbookSwapStruct.serialize({
                swap_type: DEEPBOOK_SWAP_TYPE,
                pool_id: pool,
                has_base: true,
                min_out: 0,
                base_type: base.type.substring(2),
                quote_type: quote.type.substring(2),
                lot_size: lotSize,
            }).toBytes(),
            sweepStruct.serialize({
                swap_type: SWEEP_SWAP_TYPE,
                type: base.type.substring(2),
            }).toBytes(),
            deepbookSwapStruct.serialize({
                swap_type: DEEPBOOK_SWAP_TYPE,
                pool_id: pool,
                has_base: false,
                min_out: amount,
                base_type: base.type.substring(2),
                quote_type: quote.type.substring(2),
                lot_size: lotSize,
            }).toBytes(),
            sweepStruct.serialize({
                swap_type: SWEEP_SWAP_TYPE,
                type: quote.type.substring(2),
            }).toBytes(),
        ],
        type_in: base.type.substring(2),
        destination_in: destination,
        type_out: base.type.substring(2),
        destination_out: destination,
    }).toBytes();

    const payload = defaultAbiCoder.encode(['uint256', 'bytes32', 'bytes', 'bytes', 'uint256', 'bytes'], [MESSAGE_TYPE_INTERCHAIN_TRANSFER, base.tokenId, '0x', squid_info['squid::Squid'].channel, amount, swapInfoData]);
    const receipt = await receiveCall(client, keypair, getConfig('axelar', env.alias), sourceChain, sourceAddress, its_info['its::ITS'].channel, payload);

    const quoteCoinId = receipt.objectChanges.find(change => change.type === 'created' && change.objectType === `0x2::coin::Coin<${base.type}>`).objectId;

    const quoteCoin = await client.getObject({
        id: quoteCoinId,
        options: {
            showContent: true,
        }
    });

    console.log({
        output: quoteCoin.data.content.fields.balance,
    });

}

async function registerTransaction(client, keypair, env) {
    const squid_info = getConfig('squid', env.alias);
    const itsId = getConfig('its', env.alias)['its::ITS'].objectId;
    const relayerDiscoveryId = getConfig('axelar', env.alias)['discovery::RelayerDiscovery'].objectId;
    const tx = new TransactionBlock();
    console.log(
        squid_info['squid::Squid'].objectId,
        itsId,
        relayerDiscoveryId,
    );
    tx.moveCall({
        target: `${squid_info.packageId}::discovery::register_transaction`,
        arguments: [
            tx.object(squid_info['squid::Squid'].objectId),
            tx.object(itsId),
            tx.object(relayerDiscoveryId),
        ],
        type_arguments: [],
    });

    await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForEffectsCert',
    });
}


(async() => {
    const env = parseEnv(process.argv[2] || 'localnet');
    const privKey = Buffer.from(
        process.env.SUI_PRIVATE_KEY,
        "hex"
    );

    // get the public key in a compressed format
    const keypair = Ed25519Keypair.fromSecretKey(privKey);
    // create a new SuiClient object pointing to the network you want to use
    const client = new SuiClient({ url: env.url });


    //await prepare(client, keypair, env);
    await publishPackageFull('squid', client, keypair, env);
    await registerTransaction(client, keypair, env);
    await test(client, keypair, env);
})();