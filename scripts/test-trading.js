require('dotenv').config();
const { publishInterchainToken } = require("./its/publish-interchain-token");
const { parseEnv, setConfig, getConfig } = require("./utils");
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { SuiClient } = require('@mysten/sui.js/client');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { publishPackageFull } = require('./publish-package');
const { registerInterchainToken } = require('./its/register-token');

const deepbook = '0xdee9';


const tickSize = 1e6;
const lotSize = 1e3;
const takeFeeRate = 0;
const makerRebateRate = 0;
const amountBase = 1e6*1e9;
const amountQuote = amountBase;

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
    
    await publishPackageFull('trading', client, keypair, env);

    const config = getConfig('trading', env.alias);
    
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

    let result = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
    
    const pool = result.objectChanges.find(object => object.objectType.startsWith('0xdee9::clob_v2::Pool<')).objectId;
    const poolCap = result.objectChanges.find(object => object.objectType.startsWith('0xdee9::clob_v2::PoolOwnerCap')).objectId;
    
    tx = new TransactionBlock();
    
    tx.moveCall({
        target: `${config.packageId}::trading::initialize`,
        arguments: [
            tx.object(base.treasuryCap.objectId),
            tx.object(quote.treasuryCap.objectId),
        ],
        typeArguments: [
            base.coinType,
            quote.coinType,
        ]
    });

    result = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
    const storageId = result.objectChanges[1].objectId;
    config.storage = storageId;
    config.pool = pool;
    config.baseType = base.coinType;
    config.quoteType = quote.coinType;
    setConfig('trading', env.alias, config);

    return config;
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


    await prepare(client, keypair, env);
    const config = getConfig('trading', env.alias);
    const trading = config.packageId;
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${trading}::trading::add_listing`,
        arguments: [
            tx.object(config.storage),
            tx.object(config.pool),
            tx.pure(1e9),
            tx.pure(1e10),
            tx.pure(true),
            tx.object('0x6'),
        ],
        typeArguments: [
            config.baseType,
            config.quoteType,
        ]
    });

    tx.moveCall({
            target: `${trading}::trading::swap_base`,
        arguments: [
            tx.object(config.storage),
            tx.object(config.pool),
            tx.pure(1e9),
            tx.object('0x6'),
        ],
        typeArguments: [
            config.baseType,
            config.quoteType,
        ]
    });

    result = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
    let events = await client.queryEvents({
        query: {
            MoveEventType: `${trading}::trading::Event`
        }
    });
    console.log(events.data[0].parsedJson);
    events = await client.queryEvents({
        query: {
            MoveEventType: `${trading}::trading::Balances`
        }
    });
    console.log(events.data[0].parsedJson);
})();