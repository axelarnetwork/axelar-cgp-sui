const { bcs } = require('@mysten/sui.js/bcs');
const { fromHEX, toHEX } = require('@mysten/bcs');

export const UID = bcs.fixedArray(32, bcs.u8()).transform({
    input: (id: string) => fromHEX(id),
    output: (id: number[]) => toHEX(Uint8Array.from(id)),
});
