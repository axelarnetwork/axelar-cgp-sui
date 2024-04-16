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
const amountBase = 1e6*1e9;
const amountQuote = amountBase;

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
            arguments: [tx.object(quote.objectId), tx.pure(amount)],
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

    /*for(let i=0; i<100; i++) {console.log(i);
        price = 1e9 - tickSize * Math.floor(1 + Math.random() * 10);
        amount = 1e9 * Math.floor(100 + Math.random() * 100);
        try {
            await placeLimitOrder(client, keypair, env, true, price, amount);
        } catch(e) {
            i--;
        }

    }*/

    
})();