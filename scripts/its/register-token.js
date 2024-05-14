require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { publishInterchainToken } = require('./publish-interchain-token');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const {BCS, getSuiMoveConfig} = require("@mysten/bcs");
const { getConfig } = require('../utils');

async function registerInterchainToken(client, keypair, itsInfo, name, symbol, decimals, mintAmount = false) {
    const { coinType, coinMetadata, treasuryCap } = await publishInterchainToken(client, keypair, itsInfo, name, symbol, decimals, true);

    const itsPackageId = itsInfo.packageId;
    const itsObjectId = itsInfo['its::ITS'].objectId;
    let tx = new TransactionBlock();

    if(mintAmount) {
        tx.moveCall({
            target: `0x2::coin::mint_and_transfer`,
            arguments: [
                tx.object(treasuryCap.objectId),
                tx.pure(mintAmount),
                tx.pure.address(keypair.getPublicKey().toSuiAddress()),
            ],
            typeArguments: [coinType],
        });
    }

    const coinInfo = tx.moveCall({
        target: `${itsPackageId}::coin_info::from_metadata`,
        arguments: [
            tx.object(coinMetadata.objectId),
        ],
        typeArguments: [coinType],
    });

    const coinManagement = tx.moveCall({
        target: `${itsPackageId}::coin_management::new_with_cap`,
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

    const result = await client.signAndExecuteTransactionBlock({
		transactionBlock: tx,
		signer: keypair,
		options: {
			showEffects: true,
			showObjectChanges: true,
            showContent: true
		},
        requestType: 'WaitForEffectsCert',
	});
    const coinObjectId = mintAmount ? result.objectChanges.find(object => object.objectType === `0x2::coin::Coin<${coinType}>`).objectId : null;
    
    const eventData = (await client.queryEvents({query: {
        MoveEventType: `${itsPackageId}::service::CoinRegistered<${coinType}>`,
    }}));
    const tokenId = eventData.data[0].parsedJson.token_id.id;

    return [tokenId, coinType, coinObjectId];
}

module.exports = {
    registerInterchainToken,
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
        const itsInfo = getConfig('its', env);
        const [tokenId, coinType] = await registerInterchainToken(client, keypair, itsInfo, name, symbol, decimals);

        const itsPackageId = itsInfo.packageId;
        const itsObjectId = itsInfo['its::ITS'].objectId;

        tx = new TransactionBlock();
    
        const tokenIdObj = tx.moveCall({
            target: `${itsPackageId}::token_id::from_address`,
            arguments: [
                tx.pure.address(tokenId),
            ],
            typeArguments: [],
        });

        tx.moveCall({
            target: `${itsPackageId}::its::token_name`,
            arguments: [tx.object(itsObjectId), tokenIdObj],
            typeArguments: [coinType],
        });
    
        tx.moveCall({
            target: `${itsPackageId}::its::token_symbol`,
            arguments: [tx.object(itsObjectId), tokenIdObj],
            typeArguments: [coinType],
        });
    
        tx.moveCall({
            target: `${itsPackageId}::its::token_decimals`,
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
            const decimals = bcs.de('u8', new Uint8Array(resp.results[3].returnValues[0][0]));
            console.log(name, symbol, decimals);
        }
    })();
}