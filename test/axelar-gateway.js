const { SuiClient, getFullnodeUrl } = require('@mysten/sui.js/client');
const { Ed25519Keypair } = require('@mysten/sui.js/keypairs/ed25519');
const { Secp256k1Keypair } = require('@mysten/sui.js/keypairs/secp256k1');
const { requestSuiFromFaucetV0, getFaucetHost } = require('@mysten/sui.js/faucet');
const { publishPackage, getRandomBytes32 } = require('./utils');
const { TxBuilder } = require('../dist/tx-builder');
const { bcsStructs: { axelarStructs } } = require('../dist/bcs');
const { arrayify, hexlify, keccak256 } = require('ethers/lib/utils');
const secp256k1 = require('secp256k1');

const COMMAND_TYPE_ROTATE_SIGNERS = 1;

describe.only('test', () => {
    let client;
    const operator = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const deployer = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const keypair = Ed25519Keypair.fromSecretKey(arrayify(getRandomBytes32()));
    const domainSeparator = getRandomBytes32();
    let operatorKeys;
    let signers;
    let nonce = 0;
    let packageId;


    function calculateNextSigners() {
        operatorKeys = [getRandomBytes32(), getRandomBytes32(), getRandomBytes32()];
        pubkeys = operatorKeys.map(key => Secp256k1Keypair.fromSecretKey(arrayify(key)).getPublicKey().toRawBytes());
        const keys = operatorKeys.map((key,index) => { return { privkey: key, pubkey: pubkeys[index]} });
        keys.sort((key1, key2) => {
            for(let i = 0; i < 33; i ++) {
                if (key1.pubkey[i] < key2.pubkey[i]) return -1;
                if (key1.pubkey[i] > key2.pubkey[i]) return 1;
            }
            return 0;
        });
        operatorKeys = keys.map(key => key.privkey);
        signers = {
            signers: keys.map((key) => {
                return { pubkey: key.pubkey, weight: 1 };
            }),
            threshold: 2,
            nonce: hexlify([++nonce]),
        };
    }

    function hashMessage(data) {
        const toHash = new Uint8Array(data.length + 1);
        toHash[0] = COMMAND_TYPE_ROTATE_SIGNERS;
        toHash.set(data, 1);
    
        return keccak256(toHash);
    }

    function sign(privKeys, messageToSign) {
        const signatures = [];
        for(const privKey of privKeys) {
            const { signature, recid } = secp256k1.ecdsaSign(arrayify(keccak256(messageToSign)), arrayify(privKey));
            signatures.push(new Uint8Array([...signature, recid]));
        }
        return signatures;
    }

    async function sleep(ms = 1000) {
        await new Promise((resolve) => setTimeout(resolve, ms));
    }
    
    const minimumRotationDelay = 1000;
    before(async () => {
        client = new SuiClient({ url: getFullnodeUrl('localnet') });

        await Promise.all([operator, deployer, keypair].map(
            (keypair) => requestSuiFromFaucetV0({
                host: getFaucetHost('localnet'),
                recipient: keypair.toSuiAddress(),
            })
        ))

        let result = await publishPackage(client, deployer, 'axelar_gateway');
        packageId = result.packageId;
        const creatorCap = result.publishTxn.objectChanges.find((change) => change.objectType === `${packageId}::gateway::CreatorCap`).objectId;

        calculateNextSigners();
        
        const encodedSigners = axelarStructs.WeightedSigners.serialize(signers).toBytes();
        const builder = new TxBuilder(client);

        const separator = await builder.moveCall({
            target: `${packageId}::bytes32::new`,
            arguments: [domainSeparator],
        });
    
        await builder.moveCall({
            target: `${packageId}::gateway::setup`,
            arguments: [
                creatorCap,
                operator.toSuiAddress(),
                separator,
                minimumRotationDelay,
                encodedSigners,
                '0x6',
            ]
        });

        result = await builder.signAndExecute(deployer);

        gateway = result.objectChanges.find((change) => change.objectType === `${packageId}::gateway::Gateway`).objectId;
    });
    it('Should Rotate Signers', async () => {
        await sleep(2000);
        const proofSigners = signers;
        const proofKeys = operatorKeys;
        calculateNextSigners();
        
        const encodedSigners = axelarStructs.WeightedSigners
            .serialize(signers)
            .toBytes();

        const hashed = hashMessage(encodedSigners);

        const message = axelarStructs.MessageToSign
            .serialize({
                domain_separator: domainSeparator,
                signers_hash: keccak256(axelarStructs.WeightedSigners.serialize(proofSigners).toBytes()),
                data_hash: hashed,
            })
            .toBytes();

        const signatures = sign(proofKeys, message);
        const encodedProof = axelarStructs.Proof
            .serialize({
                signers: proofSigners,
                signatures,
            })
            .toBytes();

            const builder = new TxBuilder(client);

        await builder.moveCall({
            target: `${packageId}::gateway::rotate_signers`,
            arguments: [
                gateway,
                '0x6',
                encodedSigners,
                encodedProof,
            ],
        });

        await builder.signAndExecute(keypair);
    });
});
