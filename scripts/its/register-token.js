require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { publishInterchainToken } = require('./publish-interchain-token');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const {BCS, getSuiMoveConfig} = require("@mysten/bcs");

const testInfo = require('../../info/test.json');

async function registerInterchainToken(client, keypair, testInfo, name, symbol, decimals) {
    const { coinType, coinMetadata, treasuryCap } = await publishInterchainToken(client, keypair, testInfo, name, symbol, decimals, true);

    const itsPackageId = testInfo.packageId;
    const itsObjectId = testInfo['storage::ITS'].objectId;
    let tx = new TransactionBlock();



    const coinInfo = tx.moveCall({
        target: `${itsPackageId}::coin_info::from_metadata`,
        arguments: [
            tx.object(coinMetadata.objectId),
        ],
        typeArguments: [coinType],
    });

    const coinManagement = tx.moveCall({
        target: `${itsPackageId}::coin_management::mint_burn`,
        arguments: [
            tx.object(treasuryCap.objectId),
        ],
        typeArguments: [coinType],
    });

    tx.moveCall({
        target: `${itsPackageId}::service::register_coin`,
        arguments: [
            tx.object(itsObjectId),
            coinInfo,
            coinManagement,
        ],
        typeArguments: [coinType],
    });

    await client.signAndExecuteTransactionBlock({
		transactionBlock: tx,
		signer: keypair,
		options: {
			showEffects: true,
			showObjectChanges: true,
            showContent: true
		},
	});

    const eventData = (await client.queryEvents({query: {
        MoveEventType: `${itsPackageId}::service::CoinRegistered<${coinType}>`,
    }}));
    const tokenId = eventData.data[0].parsedJson.token_id.id;

    tx = new TransactionBlock();

    const tokenIdObj = tx.moveCall({
        target: `${itsPackageId}::token_id::from_address`,
        arguments: [tx.pure(tokenId)],
    });

    tx.moveCall({
        target: `${itsPackageId}::storage::token_name`,
        arguments: [tx.object(itsObjectId), tokenIdObj],
        typeArguments: [coinType],
    });

    tx.moveCall({
        target: `${itsPackageId}::storage::token_symbol`,
        arguments: [tx.object(itsObjectId), tokenIdObj],
        typeArguments: [coinType],
    });

    tx.moveCall({
        target: `${itsPackageId}::storage::token_decimals`,
        arguments: [tx.object(itsObjectId), tokenIdObj],
        typeArguments: [coinType],
    });

    let resp = await client.devInspectTransactionBlock({
        sender: keypair.getPublicKey().toSuiAddress(),
        transactionBlock: tx,
    });

    const bcs = new BCS(getSuiMoveConfig());

    {
        const name = bcs.de('string', new Uint8Array(resp.results[1].returnValues[0][0]));
        const symbol = bcs.de('string', new Uint8Array(resp.results[2].returnValues[0][0]));
        const decimals = bcs.de('u8', new Uint8Array(resp.results[2].returnValues[0][0]));
        console.log(tokenId, name, symbol, decimals);
    }
    
    //console.log(resp.results.map(res => res.returnValues[0][0]));


}


if (require.main === module) {
    const name = process.argv[2] || 'Test Token';
    const symbol = process.argv[3] || 'TT';
    const decimals = process.argv[4] || 6;
    const env = process.argv[5] || 'localnet';
    
    (async () => {
        const privKey = 
        Buffer.from(
            process.env.SUI_PRIVATE_KEY,
            "hex"
        );
        const keypair = Ed25519Keypair.fromSecretKey(privKey);
        const address = keypair.getPublicKey().toSuiAddress();
        // create a new SuiClient object pointing to the network you want to use
        const client = new SuiClient({ url: getFullnodeUrl(env) });

        try {
            await requestSuiFromFaucetV0({
            // use getFaucetHost to make sure you're using correct faucet address
            // you can also just use the address (see Sui Typescript SDK Quick Start for values)
            host: getFaucetHost(env),
            recipient: address,
            });
        } catch (e) {
            console.log(e);
        }

        await registerInterchainToken(client, keypair, testInfo[env], name, symbol, decimals);
    })();
}