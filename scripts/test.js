const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { MIST_PER_SUI } = require('@mysten/sui.js/utils');
const {BCS, fromHEX, toHEX, getSuiMoveConfig, BcsWriter} = require("@mysten/bcs");
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { execSync } = require('child_process');
const tmp = require('tmp');
const secp256k1 = require('secp256k1');
const {
    utils: { keccak256, arrayify },
} = require('ethers');
const config = {};

async function publishPackage(packagePath, client = config.client, keypair = config.keypair) {
	// remove all controlled temporary objects on process exit
    const address = keypair.getPublicKey().toSuiAddress();
	tmp.setGracefulCleanup();

	const tmpobj = tmp.dirSync({ unsafeCleanup: true });

	const { modules, dependencies } = JSON.parse(
		execSync(
			`sui move build --dump-bytecode-as-base64 --path ${__dirname + '/' + packagePath} --install-dir ${tmpobj.name}`,
			{ encoding: 'utf-8' },
		),
	);
	const tx = new TransactionBlock();
	const cap = tx.publish({
		modules,
		dependencies,
	});

	// Transfer the upgrade capability to the sender so they can upgrade the package later if they want.
	tx.transferObjects([cap], tx.pure(address));
    const coins = await client.getCoins({owner: address});
    tx.setGasPayment(coins.data.map(coin => {
        coin.objectId = coin.coinObjectId; 
        return coin;
    }));

	const publishTxn = await client.signAndExecuteTransactionBlock({
		transactionBlock: tx,
		signer: keypair,
		options: {
			showEffects: true,
			showObjectChanges: true,
		},
	});
	if(publishTxn.effects?.status.status != 'success') throw new Error('Publish Tx failed');

	const packageId = ((publishTxn.objectChanges?.filter(
		(a) => a.type === 'published',
	)) ?? [])[0].packageId.replace(/^(0x)(0+)/, '0x');

	console.info(`Published package ${packageId} from address ${address}}`);

	return { packageId, publishTxn };
}

function getBcsForGateway() {
    const bcs = new BCS(getSuiMoveConfig());

    // input argument for the tx
    bcs.registerStructType("Input", {
        data: "vector<u8>",
        proof: "vector<u8>",
    });

    bcs.registerStructType("Proof", {
        // operators is a 33 byte / for now at least
        operators: "vector<vector<u8>>",
        weights: "vector<u128>",
        threshold: "u128",
        signatures: "vector<vector<u8>>",
    });

    // internals of the message
    bcs.registerStructType("AxelarMessage", {
        chain_id: "u64",
        command_ids: "vector<address>",
        commands: "vector<string>",
        params: "vector<vector<u8>>",
    });

    // internals of the message
    bcs.registerStructType("TransferOperatorshipMessage", {
        operators: "vector<vector<u8>>",
        weights: "vector<u128>",
        threshold: "u128",
    });
    bcs.registerStructType("GenericMessage", {
        source_chain: "string",
        source_address: "string",
        target_id: "address",
        payload_hash: "vector<u8>",
    });

    return bcs;
}

function hashMessage(data) {
    // sorry for putting it here...
    const messagePrefix = new Uint8Array(
        Buffer.from("\x19Sui Signed Message:\n", "ascii")
    );
    let hashed = new Uint8Array(messagePrefix.length + data.length);
    hashed.set(messagePrefix);
    hashed.set(data, messagePrefix.length);

    return keccak256(hashed);
}

function approveContractCallInput(sourceChain, sourceAddress, destinationAddress, payloadHash, commandId) {
    // generate privKey
    const privKey = Buffer.from(
        "9027dcb35b21318572bda38641b394eb33896aa81878a4f0e7066b119a9ea000",
        "hex"
    );

    // get the public key in a compressed format
    const pubKey = secp256k1.publicKeyCreate(privKey);

    const bcs = getBcsForGateway();
    
    const message = bcs
        .ser("AxelarMessage", {
            chain_id: 1,
            command_ids: [commandId],
            commands: ["approveContractCall"],
            params: [
                bcs
                    .ser("GenericMessage", {
                        source_chain: sourceChain,
                        source_address: sourceAddress,
                        payload_hash: payloadHash,
                        target_id: destinationAddress,
                    })
                    .toBytes(),
            ],
        })
        .toBytes();

        const hashed = fromHEX(hashMessage(message));
        const {signature, recid} = secp256k1.ecdsaSign(hashed, privKey);
        
        const proof = bcs
            .ser("Proof", {
                operators: [pubKey],
                weights: [100],
                threshold: 10,
                signatures: [new Uint8Array([...signature, recid])],
            })
            .toBytes();
        
        const input = bcs
            .ser("Input", {
                data: message,
                proof: proof,
            })
            .toBytes();
        return input;
}

async function approveContractCall(sourceChain, sourceAddress, destinationAddress, payloadHash, commandId) {
    const input = approveContractCallInput(sourceChain, sourceAddress, destinationAddress, payloadHash, commandId);
    
	const tx = new TransactionBlock(); 
    tx.moveCall({
        target: `${config.packageId}::gateway::process_commands`,
        arguments: [tx.object(config.validators.objectId), tx.pure(String.fromCharCode(...input))],
        typeArguments: [],
    });
    const approveTxn = await config.client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: config.keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
}

(async () => {
    const privKey = Buffer.from(
        "9027dcb35b21318572bda38641b394eb33896aa81878a4f0e7066b119a9ea000",
        "hex"
    );

    // get the public key in a compressed format
    config.keypair = Ed25519Keypair.fromSecretKey(privKey);
    config.address = config.keypair.getPublicKey().toSuiAddress();
    // create a new SuiClient object pointing to the network you want to use
    config.client = new SuiClient({ url: getFullnodeUrl('localnet') });

    await requestSuiFromFaucetV0({
        // use getFaucetHost to make sure you're using correct faucet address
        // you can also just use the address (see Sui Typescript SDK Quick Start for values)
        host: getFaucetHost('localnet'),
        recipient: config.address,
    });
    
    const packagePath = '../move';

    const { packageId, publishTxn } = await publishPackage(packagePath);
    config.packageId = packageId;
    config.its = publishTxn.objectChanges.find(object => (object.objectType === `${packageId}::dummy_its::ITS`));
    config.test = publishTxn.objectChanges.find(object => (object.objectType === `${packageId}::test_receive_call::Singleton`));
    config.validators = publishTxn.objectChanges.find(object => (object.objectType === `${packageId}::validators::AxelarValidators`));

    let event = (await config.client.queryEvents({query: {
        MoveEventType: `${packageId}::channel::ChannelCreated<${packageId}::dummy_its::Empty>`,
    }})).data[0];
    config.itsAddress = event.parsedJson.id;    
    event = (await config.client.queryEvents({query: {
        MoveEventType: `${packageId}::channel::ChannelCreated<${packageId}::test_receive_call::Empty>`,
    }})).data[0];
    config.testAddress = event.parsedJson.id;
    
    const payload = '0x1234';
    const payload_hash = arrayify(keccak256(payload));
    await approveContractCall('Ethereum', '0x0', config.testAddress, payload_hash, keccak256('0x00'));
 
    event = (await config.client.queryEvents({query: {
        MoveEventType: `${config.packageId}::gateway::ContractCallApproved`,
    }})).data[0].parsedJson;

	const tx = new TransactionBlock(); 
    const approvedCall = tx.moveCall({
        target: `${config.packageId}::gateway::take_approved_call`,
        arguments: [
            tx.object(config.validators.objectId), 
            tx.pure(event.cmd_id),
            tx.pure(event.source_chain),
            tx.pure(event.source_address),
            tx.pure(event.target_id),
            tx.pure(String.fromCharCode(...arrayify(payload))),
        ],
        typeArguments: [],
    });
    tx.moveCall({
        target: `${config.packageId}::test_receive_call::execute`,
        arguments: [
            tx.object(config.test.objectId),
            approvedCall,
        ],
        typeArguments: []
    });

    const executeTxn = await config.client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: config.keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
    });
    event = (await config.client.queryEvents({query: {
        MoveEventType: `${config.packageId}::test_receive_call::Executed`,
    }})).data[0].parsedJson;
    console.log(event);

    
})();