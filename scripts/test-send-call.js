require('dotenv').config();

const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');

const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { utils: { hexlify }} = require('ethers');

const { toPure, parseEnv } = require('./utils');
const { keccak256 } = require('ethers/lib/utils');


(async () => {
    const env = parseEnv(process.argv[2] || 'localnet');
    const payload = '0x' + Buffer.from((process.argv[3] || 'hello world'), 'utf8').toString('hex');
    const axelarInfo = require('../info/axelar.json')[env.alias];
    const testInfo = require('../info/test.json')[env.alias];
    const privKey = Buffer.from(
        process.env.SUI_PRIVATE_KEY,
        "hex"
    );

    // get the public key in a compressed format
    const keypair = Ed25519Keypair.fromSecretKey(privKey);
    // create a new SuiClient object pointing to the network you want to use
    const client = new SuiClient({ url: env.url });
    
    const axlearPackageId = axelarInfo.packageId;
    const testPackageId = testInfo.packageId;
    const test = testInfo['test::Singleton'];
    
    const destinationChain = 'ganache_0';
    const destinationAddress = '0x68B93045fe7D8794a7cAF327e7f855CD6Cd03BB8';
    //const payload = '0x1234';
    

	const tx = new TransactionBlock(); 

    tx.moveCall({
        target: `${testPackageId}::test::send_call`,
        arguments: [
            tx.object(test.objectId),
            tx.pure(destinationChain),
            tx.pure(destinationAddress),
            tx.pure(toPure(payload)),
        ],
        typeArguments: []
    });

    console.log(payload);

    const payloadHash = keccak256(payload);
    console.log(payloadHash);

    const executeTxn = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });

    console.log(JSON.stringify(executeTxn));
    const events = (await client.queryEvents({query: {
        MoveEventType: `${axlearPackageId}::gateway::ContractCall`,
    }}));
    console.log(events);
    const event = events.data.find(event => event.parsedJson.payload_hash === payloadHash && event.parsedJson.destination_chain == destinationChain && event.parsedJson.destination_address == destinationAddress).parsedJson;
    console.log(event);

    if ( hexlify(event.source_id) != test.channel ) throw new Error(`Emmited payload missmatch: ${hexlify(event.source)} != ${test.channel}`);
    
})();