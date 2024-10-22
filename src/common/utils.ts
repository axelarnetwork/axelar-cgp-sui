import { getFullnodeUrl } from '@mysten/sui/client';
import { getFaucetHost, requestSuiFromFaucetV0 } from '@mysten/sui/faucet';
import { arrayify, keccak256 } from 'ethers/lib/utils';
import secp256k1 from 'secp256k1';

export const fundAccountsFromFaucet = async (addresses: string[]) => {
    const promises = addresses.map(async (address) => {
        const network = process.env.NETWORK || 'localnet';

        return requestSuiFromFaucetV0({
            host: getFaucetHost(network as 'localnet' | 'devnet' | 'testnet'),
            recipient: address,
        });
    });

    return Promise.all(promises);
};

export function parseEnv(arg: string) {
    switch (arg?.toLowerCase()) {
        case 'localnet':
        case 'devnet':
        case 'testnet':
        case 'mainnet':
            return { alias: arg, url: getFullnodeUrl(arg as 'localnet' | 'devnet' | 'testnet' | 'mainnet') };
        default:
            return JSON.parse(arg);
    }
}

export function hashMessage(data: Uint8Array, commandType: number) {
    const toHash = new Uint8Array(data.length + 1);
    toHash[0] = commandType;
    toHash.set(data, 1);

    return keccak256(toHash);
}

export function signMessage(privKeys: string[], messageToSign: Uint8Array) {
    const signatures = [];

    for (const privKey of privKeys) {
        const { signature, recid } = secp256k1.ecdsaSign(arrayify(keccak256(messageToSign)), arrayify(privKey));
        signatures.push(new Uint8Array([...signature, recid]));
    }

    return signatures;
}
