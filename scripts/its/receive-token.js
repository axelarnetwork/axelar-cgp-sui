require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { BCS, getSuiMoveConfig } = require('@mysten/bcs');

const { arrayify, defaultAbiCoder } = require('ethers/lib/utils');
const { registerInterchainToken } = require('./register-token');
const { receiveCall } = require('../test-receive-call');
const { getConfig } = require('../utils');

async function receiveInterchainToken(
    client,
    keypair,
    axelarInfo,
    itsInfo,
    tokenId,
    sourceChain,
    sourceAddress,
    destinationAddress,
    amount,
) {
    const itsPackageId = itsInfo.packageId;
    const itsObjectId = itsInfo['its::ITS'].objectId;
    const channelId = itsInfo['its::ITS'].channel;

    const selector = 0;
    const payload = defaultAbiCoder.encode(
        ['uint256', 'bytes32', 'bytes', 'bytes', 'uint256', 'bytes'],
        [selector, tokenId, sourceAddress, destinationAddress, amount, '0x'],
    );

    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${itsPackageId}::its::get_trusted_address`,
        arguments: [tx.object(itsObjectId), tx.pure.string(sourceChain)],
    });

    const resp = await client.devInspectTransactionBlock({
        sender: keypair.getPublicKey().toSuiAddress(),
        transactionBlock: tx,
    });

    const bcs = new BCS(getSuiMoveConfig());

    const trustedAddress = bcs.de('string', new Uint8Array(resp.results[0].returnValues[0][0]));
    await receiveCall(client, keypair, axelarInfo, sourceChain, trustedAddress, channelId, payload);
}

if (require.main === module) {
    const env = process.argv[2] || 'localnet';

    const privKey = Buffer.from(process.env.SUI_PRIVATE_KEY, 'hex');
    const keypair = Ed25519Keypair.fromSecretKey(privKey);
    const address = keypair.getPublicKey().toSuiAddress();
    // create a new SuiClient object pointing to the network you want to use
    const client = new SuiClient({ url: getFullnodeUrl(env) });

    const sourceChain = process.argv[3] || 'Ethereum';
    const sourceAddress = process.argv[4] || '0x1234';
    const destinationAddress = process.argv[5] || address;
    const amount = process.argv[6] || 123467;
    const name = process.argv[7] || 'Test Token';
    const symbol = process.argv[8] || 'TT';
    const decimals = process.argv[9] || 6;

    (async () => {
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

        const [tokenId, coinType] = await registerInterchainToken(client, keypair, getConfig('its', env), name, symbol, decimals);

        await receiveInterchainToken(
            client,
            keypair,
            getConfig('axelar', env),
            getConfig('its', env),
            tokenId,
            sourceChain,
            sourceAddress,
            destinationAddress,
            amount,
        );

        const coins = await client.getCoins({
            owner: address,
            coinType: coinType,
        });
        const balance = coins.data[0].balance;

        console.log(balance);
    })();
}
