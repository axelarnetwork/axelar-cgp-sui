require('dotenv').config();
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { getConfig } = require('../utils');
const { defaultAbiCoder, keccak256, arrayify } = require('ethers/lib/utils');
const { getBcsForGateway, approveContractCall } = require('../gateway');
const {BCS, getSuiMoveConfig} = require("@mysten/bcs");


async function setTrustedAddresses(client, keypair, envAlias, chainNames, trustedAddresses) {
    const itsInfo = getConfig('its', envAlias);
    const itsPackageId = itsInfo.packageId;
    const itsObjectId = itsInfo['its::ITS'].objectId;

    const axelarInfo = getConfig('axelar', envAlias);
    const axelarPackageId = axelarInfo.packageId;

    const governance = getConfig('governance', envAlias)['governance::Governance'];
    
    const bcs = new BCS(getSuiMoveConfig());
    bcs.registerStructType("TrustedAddressInfo", {
        chainNames: "vector<string>",
        trustedAddresses: "vector<string>",
    });

    const trustedAddressInfo = bcs.ser('TrustedAddressInfo', {
        chainNames: chainNames,
        trustedAddresses: trustedAddresses,
    } ).toBytes();
    const payload = defaultAbiCoder.encode(['bytes32', 'bytes'], ['0x2af37a0d5d48850a855b1aaaf57f726c107eb99b40eabf4cc1ba30410cfa2f68', trustedAddressInfo]);

    const payloadHash = keccak256(payload);

    const commandId = await approveContractCall(
        client, 
        keypair,
        axelarInfo, 
        governance.trusted_source_chain, 
        governance.trusted_source_address, 
        itsInfo['its::ITS'].channel, 
        payloadHash,
    );

    let tx = new TransactionBlock();

    const approvedCall = tx.moveCall({
        target: `${axelarPackageId}::gateway::take_approved_call`,
        arguments: [
            tx.object(axelarInfo['gateway::Gateway'].objectId), 
            tx.pure.address(commandId),
            tx.pure.string(governance.trusted_source_chain),
            tx.pure.string(governance.trusted_source_address),
            tx.pure.address(itsInfo['its::ITS'].channel),
            tx.pure(bcs.ser('vector<u8>', arrayify(payload)).toBytes()),
        ],
        typeArguments: [],
    });
    tx.moveCall({
        target: `${itsPackageId}::service::set_trusted_addresses`,
        arguments: [
            tx.object(itsObjectId), 
            tx.object(governance.objectId),
            approvedCall,
        ],
        typeArguments: [],
    });

    await client.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        signer: keypair,
        options: {
            showEffects: true,
            showObjectChanges: true,
        },
        requestType: 'WaitForLocalExecution',
    });
}

module.exports = {
    setTrustedAddresses,
}


if (require.main === module) {
    const env = process.argv[2] || 'localnet';
    const chainName = process.argv[3] || 'Ethereum';
    const trustedAddress = process.argv[4] || '0x1234';
    
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

        await setTrustedAddresses(client, keypair, env, [chainName], [trustedAddress]);
    })();
}