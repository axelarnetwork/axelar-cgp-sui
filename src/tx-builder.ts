import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { bcs, BcsType } from '@mysten/bcs';
import {
    DevInspectResults,
    SuiClient,
    SuiMoveNormalizedType,
    SuiObjectChange,
    SuiTransactionBlockResponse,
    SuiTransactionBlockResponseOptions,
} from '@mysten/sui/client';
import { Keypair } from '@mysten/sui/dist/cjs/cryptography';
import { Transaction, TransactionObjectInput, TransactionResult } from '@mysten/sui/transactions';
import { Bytes, utils as ethersUtils } from 'ethers';
import { updateMoveToml } from './utils';

const stdPackage = '0x1';
const suiPackage = '0x2';

const { arrayify, hexlify } = ethersUtils;

const objectCache = {} as { [id in string]: SuiObjectChange };

function updateCache(objectChanges: SuiObjectChange[]) {
    for (const change of objectChanges) {
        if (change.type === 'published') {
            continue;
        }

        objectCache[change.objectId] = change;
    }
}

function getObject(tx: Transaction, object: TransactionObjectInput): TransactionObjectInput {
    if (Array.isArray(object)) {
        object = hexlify(object);
    }

    if (typeof object === 'string') {
        const cached = objectCache[object];

        if (cached) {
            // TODO: figure out how to load the object version/digest into the TransactionBlock because it seems impossible for non gas payment objects
            const txObject = tx.object(object);
            return txObject;
        }

        return tx.object(object);
    }

    return object;
}

function getTypeName(type: SuiMoveNormalizedType): string {
    type Type = { address: string; module: string; name: string; typeArguments: string[] };

    function get(type: Type) {
        let name = `${type.address}::${type.module}::${type.name}`;

        if (type.typeArguments.length > 0) {
            name += `<${type.typeArguments.join(',')}>`;
        }

        return name;
    }

    if ('Struct' in (type as object)) {
        return get((type as { Struct: Type }).Struct);
    } else if ('Reference' in (type as object)) {
        return getTypeName((type as { Reference: SuiMoveNormalizedType }).Reference);
    } else if ('MutableReference' in (type as object)) {
        return getTypeName((type as { MutableReference: SuiMoveNormalizedType }).MutableReference);
    } else if ('Vector' in (type as object)) {
        return `vector<${getTypeName((type as { Vector: SuiMoveNormalizedType }).Vector)}>`;
    }

    return (type as string).toLowerCase();
}

function getNestedStruct(tx: Transaction, type: SuiMoveNormalizedType, arg: TransactionObjectInput): null | TransactionObjectInput {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let inside = type as any;

    while ((inside as { Vector: SuiMoveNormalizedType }).Vector) {
        inside = inside.Vector;
    }

    if (!inside.Struct && !inside.Reference && !inside.MutableReference) {
        return null;
    }

    if (isString(inside)) {
        return null;
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    if ((type as any).Struct || (type as any).Reference || (type as any).MutableReference) {
        return getObject(tx, arg);
    }

    if (!(type as { Vector: SuiMoveNormalizedType }).Vector) return null;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const nested = (arg as any).map((arg: any) => getNestedStruct(tx, (type as any).Vector, arg));
    const typeName = getTypeName((type as { Vector: SuiMoveNormalizedType }).Vector);
    return tx.makeMoveVec({
        type: typeName,
        elements: nested,
    });
}

function serialize(
    tx: Transaction,
    type: SuiMoveNormalizedType,
    arg: TransactionObjectInput,
):
    | TransactionObjectInput
    | {
          index: number;
          kind: 'Input';
          type: 'pure';
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          value?: any;
      } {
    const struct = getNestedStruct(tx, type, arg);

    if (struct) {
        return struct;
    }

    const vectorU8 = () =>
        bcs.vector(bcs.u8()).transform({
            input(val: unknown) {
                if (typeof val === 'string') val = arrayify(val);
                return val as Iterable<number> & { length: number };
            },
            output(value: number[]) {
                return hexlify(value);
            },
        });

    const serializer = (type: SuiMoveNormalizedType): BcsType<unknown, unknown> => {
        if (isString(type)) {
            return bcs.string() as BcsType<unknown, unknown>;
        }

        if (typeof type === 'string') {
            if (type === 'Address') {
                return bcs.fixedArray(32, bcs.u8()).transform({
                    input: (id) => arrayify(id as number),
                    output: (id) => hexlify(id),
                });
            }

            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            return (bcs as any)[(type as string).toLowerCase()]();
        } else if ((type as { Vector: SuiMoveNormalizedType }).Vector) {
            if ((type as { Vector: SuiMoveNormalizedType }).Vector === 'U8') {
                return vectorU8() as BcsType<unknown, unknown>;
            }

            return bcs.vector(serializer((type as { Vector: SuiMoveNormalizedType }).Vector)) as BcsType<unknown, unknown>;
        }

        throw new Error(`Type ${JSON.stringify(type)} cannot be serialized`);
    };

    return tx.pure(serializer(type).serialize(arg).toBytes());
}

function isTxContext(parameter: SuiMoveNormalizedType): boolean {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let inside = parameter as any;

    if (inside.MutableReference) {
        inside = inside.MutableReference.Struct;
        if (!inside) return false;
    } else if (inside.Reference) {
        inside = inside.Reference.Struct;
        if (!inside) return false;
    } else {
        return false;
    }

    return inside.address === suiPackage && inside.module === 'tx_context' && inside.name === 'TxContext';
}

function isString(parameter: SuiMoveNormalizedType): boolean {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let asAny = parameter as any;
    if (asAny.MutableReference) parameter = asAny.MutableReference;
    if (asAny.Reference) asAny = asAny.Reference;
    asAny = asAny.Struct;
    if (!asAny) return false;
    const isAsciiString = asAny.address === stdPackage && asAny.module === 'ascii' && asAny.name === 'String';
    const isStringString = asAny.address === stdPackage && asAny.module === 'string' && asAny.name === 'String';
    return isAsciiString || isStringString;
}

export class TxBuilder {
    client: SuiClient;
    tx: Transaction;
    constructor(client: SuiClient) {
        this.client = client;
        this.tx = new Transaction();
    }

    async moveCall(moveCallInfo: {
        arguments?: TransactionObjectInput[];
        typeArguments?: string[];
        target: `${string}::${string}::${string}` | { package: string; module: string; function: string };
    }): Promise<TransactionResult> {
        let target = moveCallInfo.target;

        // If target is string, convert to object that `getNormalizedMoveFunction` accepts.
        if (typeof target === 'string') {
            const first = target.indexOf(':');
            const last = target.indexOf(':', first + 2);
            const packageId = target.slice(0, first);
            const module = target.slice(first + 2, last);
            const functionName = target.slice(last + 2);
            target = {
                package: packageId,
                module,
                function: functionName,
            };
        }

        const moveFn = await this.client.getNormalizedMoveFunction(target);

        let length = moveFn.parameters.length;
        if (isTxContext(moveFn.parameters[length - 1])) length = length - 1;
        if (!moveCallInfo.arguments) moveCallInfo.arguments = [];
        if (length !== moveCallInfo.arguments.length)
            throw new Error(
                `Function ${target.package}::${target.module}::${target.function} takes ${moveFn.parameters.length} arguments but given ${moveCallInfo.arguments.length}`,
            );

        const convertedArgs = moveCallInfo.arguments.map((arg, index) => serialize(this.tx, moveFn.parameters[index], arg));

        return this.tx.moveCall({
            target: `${target.package}::${target.module}::${target.function}`,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            arguments: convertedArgs as any,
            typeArguments: moveCallInfo.typeArguments,
        });
    }

    /**
     * Prepare a move build by creating a temporary directory to store the compiled move code
     * @returns {tmpdir: string, rmTmpDir: () => void}
     * - tmpdir is the path to the temporary directory
     * - rmTmpDir is a function to remove the temporary directory
     */
    private prepareMoveBuild() {
        const tmpdir = fs.mkdtempSync(`${__dirname}/.move-build-`);
        const rmTmpDir = () => fs.rmSync(tmpdir, { recursive: true });

        return {
            tmpdir,
            rmTmpDir,
        };
    }

    async getContractBuild(
        packageName: string,
        moveDir: string = `${__dirname}/../move`,
    ): Promise<{ modules: string[]; dependencies: string[]; digest: Bytes }> {
        const emptyPackageId = '0x0';
        updateMoveToml(packageName, emptyPackageId, moveDir);

        const { tmpdir, rmTmpDir } = this.prepareMoveBuild();

        const { modules, dependencies, digest } = JSON.parse(
            execSync(`sui move build --dump-bytecode-as-base64 --path ${path.join(moveDir, packageName)} --install-dir ${tmpdir}`, {
                encoding: 'utf-8',
                stdio: 'pipe', // silent the output
            }),
        );

        rmTmpDir();

        return { modules, dependencies, digest };
    }

    async publishPackage(packageName: string, moveDir: string = `${__dirname}/../move`): Promise<TransactionResult> {
        const { modules, dependencies } = await this.getContractBuild(packageName, moveDir);

        return this.tx.publish({
            modules,
            dependencies,
        });
    }

    async publishPackageAndTransferCap(packageName: string, to: string, moveDir = `${__dirname}/../move`) {
        const cap = await this.publishPackage(packageName, moveDir);

        this.tx.transferObjects([cap], to);
    }

    async signAndExecute(keypair: Keypair, options: SuiTransactionBlockResponseOptions): Promise<SuiTransactionBlockResponse> {
        let result = await this.client.signAndExecuteTransaction({
            transaction: this.tx,
            signer: keypair,
            options: {
                showEffects: true,
                showObjectChanges: true,
                ...options,
            },
        });

        if (!result.confirmedLocalExecution) {
            while (true) {
                try {
                    result = await this.client.getTransactionBlock({
                        digest: result.digest,
                        options: {
                            showEffects: true,
                            showObjectChanges: true,
                            ...options,
                        },
                    });
                    break;
                } catch (e) {
                    console.log(e);
                    await new Promise((resolve) => setTimeout(resolve, 1000));
                }
            }
        }

        updateCache(result.objectChanges as SuiObjectChange[]);
        return result;
    }

    async devInspect(sender: string): Promise<DevInspectResults> {
        const result = await this.client.devInspectTransactionBlock({
            transactionBlock: this.tx,
            sender,
        });
        return result;
    }
}
