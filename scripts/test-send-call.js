require('dotenv').config();

const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');

const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { utils: { hexlify }} = require('ethers');

const { toPure } = require('./utils');


(async () => {
    const env = process.argv[2] || 'localnet';
    const axelarInfo = require('../info/axelar.json')[env];
    const testInfo = require('../info/test.json')[env];
    const privKey = Buffer.from(
        process.env.SUI_PRIVATE_KEY,
        "hex"
    );

    // get the public key in a compressed format
    const keypair = Ed25519Keypair.fromSecretKey(privKey);
    // create a new SuiClient object pointing to the network you want to use
    const client = new SuiClient({ url: getFullnodeUrl(env) });
    
    const axlearPackageId = axelarInfo.packageId;
    const testPackageId = testInfo.packageId;
    const test = testInfo['test::Singleton'];
    
    const destinationChain = 'ethereum';
    const destinationAddress = '0x123456';
    const payload = '0x1234';
    

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

    const executeTxn = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
    const event = (await client.queryEvents({query: {
        MoveEventType: `${axlearPackageId}::gateway::ContractCall`,
    }})).data[0].parsedJson;
    console.log(event);

    if ( hexlify(event.source_id) != test.channel ) throw new Error(`Emmited payload missmatch: ${hexlify(event.source)} != ${test.channel}`);
    
})();