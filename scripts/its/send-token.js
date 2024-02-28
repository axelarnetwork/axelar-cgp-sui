require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const {BCS, getSuiMoveConfig} = require("@mysten/bcs");

const { registerInterchainToken } = require('./register-token');
const { arrayify, defaultAbiCoder } = require('ethers/lib/utils');
const { getConfig } = require('../utils');

async function sendInterchainToken(client, keypair, itsInfo, tokenId, coin, destinationChain, destiantionAddress) {
    const itsPackageId = itsInfo.packageId;
    const itsObjectId = itsInfo['its::ITS'].objectId;

    let tx = new TransactionBlock();

    let tokenIdObj = tx.moveCall({
        target: `${itsPackageId}::token_id::from_address`,
        arguments: [
            tx.pure(tokenId),
        ],
        typeArguments: [],
    });

    tx.moveCall({
        target: `${itsPackageId}::its::get_registered_coin_type`,
        arguments: [
            tx.object(itsObjectId),
            tokenIdObj,
        ],
        typeArguments: [],
    });

    let resp = await client.devInspectTransactionBlock({
        sender: keypair.getPublicKey().toSuiAddress(),
        transactionBlock: tx,
    });

    const bcs = new BCS(getSuiMoveConfig());

    const coinType = bcs.de('string', new Uint8Array(resp.results[1].returnValues[0][0]));

    tx = new TransactionBlock();

    tokenIdObj = tx.moveCall({
        target: `${itsPackageId}::token_id::from_address`,
        arguments: [
            tx.pure(tokenId),
        ],
        typeArguments: [],
    });

    tx.moveCall({
        target: `${itsPackageId}::service::interchain_transfer`,
        arguments: [
            tx.object(itsObjectId),
            tokenIdObj,
            tx.object(coin),
            tx.pure.string(destinationChain),
            tx.pure(String.fromCharCode(...arrayify(destiantionAddress))),
            tx.pure(''),
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
}


if (require.main === module) {
    const env = process.argv[2] || 'localnet';
    const destinationChain = process.argv[3] || 'Ethereum';
    const destiantionAddress = process.argv[4] || '0x1234';
    const amount = process.argv[5] || 1234;
    const name = process.argv[6] || 'Test Token';
    const symbol = process.argv[7] || 'TT';
    const decimals = process.argv[8] || 6;

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
        const axelarInfo = getConfig('axelar', env);

        const [tokenId, coinType] = await registerInterchainToken(client, keypair, itsInfo, name, symbol, decimals, amount);

        let resp = await client.getCoins({
            owner: keypair.getPublicKey().toSuiAddress(),
            coinType: coinType,
        });
        coin = resp.data[0].coinObjectId;

        await sendInterchainToken(client, keypair, itsInfo, tokenId, coin, destinationChain, destiantionAddress);

        const eventData = (await client.queryEvents({query: {
            MoveEventType: `${axelarInfo.packageId}::gateway::ContractCall`,
        }}));
        const payload = eventData.data[0].parsedJson.payload;
        {
            const [, tokenId, sourceAddress, destinationAddress, amount, data] = defaultAbiCoder.decode(['uint256', 'bytes32', 'bytes', 'bytes', 'uint256', 'bytes'], payload);
            console.log([tokenId, sourceAddress, destinationAddress, Number(amount), data]);
        }
    })();
}
