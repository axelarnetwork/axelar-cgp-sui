require('dotenv').config();

const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const {BCS, fromHEX, getSuiMoveConfig} = require("@mysten/bcs");
const {
    utils: { keccak256, arrayify, hexlify },
} = require('ethers');
const { approveContractCall } = require('./gateway');
const { toPure } = require('./utils');


function getCalInfoFunFromType(type) {
    const lastCol = type.lastIndexOf(':');
    return type.slice(0, lastCol + 1) + 'get_call_info';
}

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
    
    const axelarPackageId = axelarInfo.packageId;
    const validators = axelarInfo['validators::AxelarValidators'];
    const testPackageId = testInfo.packageId;
    const test = testInfo['test::Singleton'];
    
    const payload = '0x1234';
    const payload_hash = keccak256(payload);
    await approveContractCall(env, client, keypair, 'Ethereum', '0x0', test.channel, payload_hash);
 
    const eventData = (await client.queryEvents({query: {
        MoveEventType: `${axelarPackageId}::gateway::ContractCallApproved`,
    }}));
    let event = eventData.data[0].parsedJson;

    const callInfoObject = await client.getObject({id: event.target_id, options: {showContent: true}});
    const callObjectIds = callInfoObject.data.content.fields.get_call_info_object_ids;
    const infoTarget = getCalInfoFunFromType(callInfoObject.data.content.type);

    let tx = new TransactionBlock();
    tx.moveCall({
        target: infoTarget,
        arguments: [tx.pure(String.fromCharCode(...arrayify(payload))), ...callObjectIds.map(id => tx.object(id))],
    });
    const resp = await client.devInspectTransactionBlock({
        sender: keypair.getPublicKey().toSuiAddress(),
        transactionBlock: tx,
        
    });
    const bcs_encoded_resp = resp.results[0].returnValues[0][0];
    const bcs = new BCS(getSuiMoveConfig());
    const decoded = bcs.de(BCS.STRING, new Uint8Array(bcs_encoded_resp));
    const toCall = JSON.parse(decoded);
    
	tx = new TransactionBlock(); 
    const approvedCall = tx.moveCall({
        target: `${axelarPackageId}::gateway::take_approved_call`,
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

    toCall.arguments = toCall.arguments.map(arg => {
        if(typeof arg !== 'string') {
            return tx.pure(arg);
        }
        if(arg == 'contractCall') {
            return approvedCall;
        }
        if(arg.slice(0,4) === 'obj:') {
            return tx.object(arg.slice(4));
        }
        if(arg.slice(0,5) === 'pure:') {
            return tx.pure(arg.slice(5));
        }
    });

    tx.moveCall(toCall);

    await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
    event = (await client.queryEvents({query: {
        MoveEventType: `${testPackageId}::test::Executed`,
    }})).data[0].parsedJson;
    
    if ( hexlify(event.data) != payload ) throw new Error(`Emmited payload missmatch: ${hexlify(event.data)} != ${payload}`);
    console.log('Success!');
    
})();