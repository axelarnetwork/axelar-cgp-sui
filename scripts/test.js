
const {fromHEX} = require("@mysten/bcs");
const { hexlify, keccak256, arrayify } = require("ethers/lib/utils");
const { getBcsForGateway, getRandomOperators, hashMessage } = require("./gateway");
const secp256k1 = require('secp256k1');


const bcs = getBcsForGateway()

const privKeys = [
    'f1677dbe70630c80f90beeb0c1a7f03a4ae721291f4a41ef4f299789d6323ee0',
    '9dedf3d3ab862be4128a6a7cbd92ef7a18bb1e16642265caf4edaf513a2bf5de',
    '43e7ccbb0e634943897113104c13d3c0776460d9f48403d447f05504a38ac5ee',
];
const weights = [3, 3, 3];
const threshold = 7;
const message = '0x123456';

// get the public key in a compressed format
const pubKeys = privKeys.map(privKey => secp256k1.publicKeyCreate(Buffer.from(privKey, 'hex')));

const hashed = fromHEX(hashMessage(arrayify(message)));
const signatures = privKeys.map(privKey => {
    const {signature, recid} = secp256k1.ecdsaSign(hashed, Buffer.from(privKey, 'hex'));
    return new Uint8Array([...signature, recid]);
})

const proof =  bcs
    .ser("Proof", {
        operators: pubKeys,
        weights: weights,
        threshold: threshold,
        signatures,
    })
    .toBytes();
const payload = bcs.ser("TransferOperatorshipMessage", {
    operators: pubKeys,
    weights: weights,
    threshold: threshold,
})
.toBytes()
console.log(hexlify(proof).substring(2));
console.log();
console.log(hexlify(payload).substring(2));
console.log();
console.log(hexlify(message).substring(2));
console.log()
console.log(pubKeys.map(pubKey => hexlify(pubKey)));
console.log(hashed);
