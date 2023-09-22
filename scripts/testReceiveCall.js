require('dotenv').config();

const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const {
    utils: { keccak256, arrayify, hexlify },
} = require('ethers');
const axelarInfo = require('../info/axelar.json');
const { approveContractCall } = require('./gateway');


(async () => {
    const privKey = Buffer.from(
        process.env.SUI_PRIVATE_KEY,
        "hex"
    );

    // get the public key in a compressed format
    const keypair = Ed25519Keypair.fromSecretKey(privKey);
    // create a new SuiClient object pointing to the network you want to use
    const client = new SuiClient({ url: getFullnodeUrl('localnet') });
    
    const packageId = axelarInfo.packageId;
    const validators = axelarInfo['validators::AxelarValidators'];
    const test = axelarInfo['test_receive_call::Singleton'];
    
    const payload = '0x1234';
    const payload_hash = arrayify(keccak256(payload));
    await approveContractCall(client, keypair, 'Ethereum', '0x0', test.channel, payload_hash);
 
    let event = (await client.queryEvents({query: {
        MoveEventType: `${packageId}::gateway::ContractCallApproved`,
    }})).data[0].parsedJson;
    console.log(event)

	const tx = new TransactionBlock(); 
    const approvedCall = tx.moveCall({
        target: `${packageId}::gateway::take_approved_call`,
        arguments: [
            tx.object(validators.objectId), 
            tx.pure(event.cmd_id),
            tx.pure(event.source_chain),
            tx.pure(event.source_address),
            tx.pure(event.target_id),
            tx.pure(String.fromCharCode(...arrayify(payload))),
        ],
        typeArguments: [],
    });
    tx.moveCall({
        target: `${packageId}::test_receive_call::execute`,
        arguments: [
            tx.object(test.objectId),
            approvedCall,
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
    event = (await client.queryEvents({query: {
        MoveEventType: `${packageId}::test_receive_call::Executed`,
    }})).data[0].parsedJson;
    
    if ( hexlify(event.data) != payload ) throw new Error(`Emmited payload missmatch: ${hexlify(event.data)} != ${payload}`);

    
})();