import { getFullnodeUrl, SuiMoveNormalizedType } from '@mysten/sui/client';
import { getFaucetHost, requestSuiFromFaucetV0, requestSuiFromFaucetV2 } from '@mysten/sui/faucet';
import { arrayify, keccak256 } from 'ethers/lib/utils';
import secp256k1 from 'secp256k1';
import { STD_PACKAGE_ID } from './types';

export const fundAccountsFromFaucet = async (addresses: string[]) => {
    const promises = addresses.map(async (address) => {
        const network = process.env.NETWORK || 'localnet';

        switch (network) {
            case 'localnet': {
                /// @deprecated: requestSuiFromFaucetV0
                return requestSuiFromFaucetV0({
                    host: getFaucetHost('localnet'),
                    recipient: address,
                });
            }

            case 'mainnet': {
                throw new Error(`Faucet request failed, invalid network: ${network}`);
            }

            default: {
                return requestSuiFromFaucetV2({
                    host: getFaucetHost(network as 'devnet' | 'testnet'),
                    recipient: address,
                });
            }
        }
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

export function isString(parameter: SuiMoveNormalizedType): boolean {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let asAny = parameter as any;

    if (asAny.MutableReference) {
        parameter = asAny.MutableReference;
    }

    if (asAny.Reference) {
        asAny = asAny.Reference;
    }

    asAny = asAny.Struct;

    if (!asAny) {
        return false;
    }

    const isAsciiString = asAny.address === STD_PACKAGE_ID && asAny.module === 'ascii' && asAny.name === 'String';
    const isStringString = asAny.address === STD_PACKAGE_ID && asAny.module === 'string' && asAny.name === 'String';
    return isAsciiString || isStringString;
}
