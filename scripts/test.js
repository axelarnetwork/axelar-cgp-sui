const { defaultAbiCoder } = require("ethers/lib/utils");



const payload = defaultAbiCoder.encode(['bytes[]'], [['0x12', '0x04']]);
for(let i=0; i * 64 + 2 < payload.length; i++) {
    console.log(payload.substring(2 + i * 64, 66 + i * 64));
}
console.log(payload.substring(2))
