const objectCache = {};

function updateCache(txResponse) {
    for(const change of txResponse.objectChanges) {
        objectCache[change.objectId] = change;
    }
}

function getObject(objectId) {
    return objectCache[objectId];
}

function serialize (type, arg) {
    bcs.address = () => bcs.fixedArray(32, bcs.u8()).transform({
        input: (id) => arrayify(id),
        output: (id) => hexlify(id),
    });

    const vectorU8 = () => bcs.vector(bcs.u8()).transform({
        input: (input) => {
            if(typeof(input) === 'string') input = arrayify(input);
            return bcs.vector(bcs.u8()).serialize(input).toBytes();
        }
    })

    const serializer = (type) => {
        if (typeof(type) === 'string') {
            return bcs[type]();
        } else if (type.Vector) {
            if(type.Vector === 'U8') {
                return vectorU8();
            }
            return bcs.vector(serializer(type.Vector));
        } else {
            return null;
        }
    }
    return serializer(type).serialize(arg).toBytes();
}

function TxBuilder() {
    let tx;
    let client;
    let keypair;
    async function moveCall(target, arguments, typeArguments) {
        // If target is string, convert to object that `getNormalizedMoveFunction` accepts.
        if(typeof(target) === 'string') {
            const first = target.indexOf(':');
            const last = target.indexOf(':', first + 2);
            const packageId = target.slice(0, first);
            const module = target.slice(first + 2, last);
            const functionName = target.slice(last + 2);
            target = {
                packageId,
                module,
                function: functionName,
            }
        }
        const moveFn = await client.getNormalizedMoveFunction(target);

    }
}



module.exports = {
    updateCache,
    getObject,
}