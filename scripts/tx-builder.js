const { TransactionBlock } = require('@mysten/sui.js/transactions');
const { bcs } = require('@mysten/bcs');
const {
    utils: { arrayify, hexlify },
} = require('ethers');
const tmp = require('tmp');
const path = require('path');

const objectCache = {};

function updateCache(objectChanges) {
    for (const change of objectChanges) {
        if (!change.objectId) continue;
        objectCache[change.objectId] = change;
    }
}

function getObject(tx, object) {
    if (Array.isArray(object)) {
        object = hexlify(object);
    }

    if (typeof object === 'string') {
        const cached = objectCache[object];

        if (cached) {
            return tx.object(cached);
        }

        return tx.object(object);
    }

    return object;
}

function getTypeName(type) {
    function get(type) {
        let name = `${type.address}::${type.module}::${type.name}`;

        if (type.typeArguments.length > 0) {
            name += `<${type.typeArguments[0]}`;

            for (let i = 1; i < type.typeArguments.length; i++) {
                name += `,${type.typeArguments[i]}`;
            }

            name += '>';
        }

        return name;
    }

    if (type.Struct) {
        return get(type.Struct);
    } else if (type.Reference) {
        return getTypeName(type.Reference);
    } else if (type.MutableReference) {
        return getTypeName(type.MutableReference);
    } else if (type.Vector) {
        return `vector<${getTypeName(type.Vector)}>`;
    }

    return type.toLowerCase();
}

function getNestedStruct(tx, type, arg) {
    let inside = type;

    while (inside.Vector) {
        inside = inside.Vector;
    }

    if (!inside.Struct && !inside.Reference && !inside.MutableReference) {
        return null;
    }

    if (isString(inside)) {
        return null;
    }

    if (type.Struct || type.Reference || type.MutableReference) {
        return getObject(tx, arg);
    }

    if (!type.Vector) return null;
    const nested = arg.map((arg) => getNestedStruct(tx, type.Vector, arg));
    const typeName = getTypeName(type.Vector);
    return tx.makeMoveVec({
        type: typeName,
        objects: nested,
    });
}

function serialize(tx, type, arg) {
    const struct = getNestedStruct(tx, type, arg);

    if (struct) {
        return struct;
    }

    bcs.address = () =>
        bcs.fixedArray(32, bcs.u8()).transform({
            input: (id) => arrayify(id),
            output: (id) => hexlify(id),
        });

    const vectorU8 = () =>
        bcs.vector(bcs.u8()).transform({
            input(input) {
                if (typeof input === 'string') input = arrayify(input);
                return input;
            },
        });

    const serializer = (type) => {
        if (isString(type)) {
            return bcs.string();
        }

        if (typeof type === 'string') {
            return bcs[type.toLowerCase()]();
        } else if (type.Vector) {
            if (type.Vector === 'U8') {
                return vectorU8();
            }

            return bcs.vector(serializer(type.Vector));
        }

        return null;
    };

    return tx.pure(serializer(type).serialize(arg).toBytes());
}

function isTxContext(parameter) {
    parameter = parameter.MutableReference;
    if (!parameter) return false;
    parameter = parameter.Struct;
    if (!parameter) return false;
    return parameter.address === '0x2' && parameter.module === 'tx_context' && parameter.name === 'TxContext';
}

function isString(parameter) {
    if (parameter.MutableReference) parameter = parameter.MutableReference;
    if (parameter.Reference) parameter = parameter.Reference;
    parameter = parameter.Struct;
    if (!parameter) return false;
    const isAsciiString = parameter.address === '0x1' && parameter.module === 'ascii' && parameter.name === 'String';
    const isStringString = parameter.address === '0x1' && parameter.module === 'string' && parameter.name === 'String';
    return isAsciiString || isStringString;
}

class TxBuilder {
    constructor(client) {
        this.client = client;
        this.tx = new TransactionBlock();
    }

    async moveCall({target, args, typeArguments = []}) {
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
        if (length !== args.length)
            throw new Error(
                `Function ${target.package}::${target.module}::${target.function} takes ${moveFn.parameters.length} arguments but given ${args.length}`,
            );

        const convertedArgs = args.map((arg, index) => serialize(this.tx, moveFn.parameters[index], arg));

        return this.tx.moveCall({
            target: `${target.package}::${target.module}::${target.function}`,
            arguments: convertedArgs,
            typeArguments,
        });
    }

    async publishPackage(packageName, moveDir = `${__dirname}/../move`) {
        updateMoveToml(packageName, '0x0', moveDir);

        tmp.setGracefulCleanup();

        const tmpobj = tmp.dirSync({ unsafeCleanup: true });

        const { modules, dependencies } = JSON.parse(
            execSync(
                `sui move build --dump-bytecode-as-base64 --path ${path.join(moveDir, packageName)} --install-dir ${
                    tmpobj.name
                }`,
                {
                    encoding: 'utf-8',
                    stdio: 'pipe', // silent the output
                },
            ),
        );
        

        const tx = new TransactionBlock();
        return tx.publish({
            modules,
            dependencies,
        });
    }

    async publishPackageAndTransferCap(packageName, to, moveDir = `${__dirname}/../move`) {
        updateMoveToml(packageName, '0x0', moveDir);

        tmp.setGracefulCleanup();

        const tmpobj = tmp.dirSync({ unsafeCleanup: true });

        const { modules, dependencies } = JSON.parse(
            execSync(
                `sui move build --dump-bytecode-as-base64 --path ${path.join(moveDir, packageName)} --install-dir ${
                    tmpobj.name
                }`,
                {
                    encoding: 'utf-8',
                    stdio: 'pipe', // silent the output
                },
            ),
        );
        

        const tx = new TransactionBlock();
        const cap = tx.publish({
            modules,
            dependencies,
        });

        tx.transferObjects([cap], to);
    }

    async signAndExecute(keypair, options) {
        const result = await this.client.signAndExecuteTransactionBlock({
            transactionBlock: this.tx,
            signer: keypair,
            options: {
                showEffects: true,
                showObjectChanges: true,
                showContent: true,
                ...options,
            },
        });
        updateCache(result.objectChanges);
        return result;
    }

    async devInspect(sender, options) {
        const result = await this.client.devInspectTransactionBlock({
            transactionBlock: this.tx,
            sender,

            options: {
                showEffects: true,
                showObjectChanges: true,
                showContent: true,
                ...options,
            },
        });
        return result;
    }
}

module.exports = {
    TxBuilder,
};
