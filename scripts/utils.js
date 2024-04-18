const { arrayify } = require('ethers/lib/utils');
const fs = require('fs');

const configs = {};
const { getFullnodeUrl } = require('@mysten/sui.js/client');
const { requestSuiFromFaucetV0, getFaucetHost, getFaucetRequestStatus } = require('@mysten/sui.js/faucet');

function toPure(hexString) {
    return String.fromCharCode(...arrayify(hexString));
}

function getModuleNameFromSymbol(symbol) {
    function isNumber(char) {
        return char >= '0' && char <= '9';
    }
    function isLowercase(char) {
        return char >= 'a' && char <= 'z';
    }
    function isUppercase(char) {
        return char >= 'A' && char <= 'Z';
    }

    let i = 0;
    let length = symbol.length;
    let moduleName = ''

    while(isNumber(symbol[i])) {
        i++;
    };
    while(i < length) {
        let char = symbol[i];
        if( isLowercase(char) || isNumber(char) ) {
            moduleName += char;
        } else if( isUppercase(char) ) {
            moduleName += char.toLowerCase();
        } else if(char == '_' || char == ' ') {
            moduleName += '_';
        };
        i++;
    };
    return moduleName;
}

function getConfig(packagePath, envAlias) {
    if(!configs[packagePath]) {
        configs[packagePath] = fs.existsSync(`${__dirname}/../info/${packagePath}.json`) ? JSON.parse(fs.readFileSync(`${__dirname}/../info/${packagePath}.json`)) : {};
    }

    return configs[packagePath][envAlias];
}

function setConfig(packagePath, envAlias, config) {
    if(!configs[packagePath]) {
        configs[packagePath] = fs.existsSync(`${__dirname}/../info/${packagePath}.json`) ? require(`${__dirname}/../info/${packagePath}.json`) : {};
    }
    configs[packagePath][envAlias] = config;

    if (!fs.existsSync(`${__dirname}/../info`)){
        fs.mkdirSync(`${__dirname}/../info`);
    }
    fs.writeFileSync(`${__dirname}/../info/${packagePath}.json`, JSON.stringify(configs[packagePath], null, 4));
}

async function requestSuiFromFaucet(env, address) {
    try {
        const resp = await requestSuiFromFaucetV0({
            // use getFaucetHost to make sure you're using correct faucet address
            // you can also just use the address (see Sui Typescript SDK Quick Start for values)
            host: getFaucetHost(env.alias),
            recipient: address,
        });
    } catch (e) {
        console.log(e);
    }
}

async function getFullObject(object, client) {
    for(const field of ['type', 'sender', 'owner']) {
        if(object[field]) {
            delete object[field];
        }
    }
    const objectResponce = await client.getObject({
        id: object.objectId,
        options: {
            showContent: true,
        }
    });
    const fields = objectResponce.data.content.fields;

    function decodeFields(fields, object) {
        for(const key in fields) {
            if(key === 'id') continue;
            if(fields[key].fields) {
                if(!fields[key].fields.id) {
                    object[key] = {};
                    decodeFields(fields[key].fields, object[key]);
                } else {
                    object[key] = fields[key].fields.id.id || fields[key].fields.id;
                }
            } else if(fields[key].id) {
                object[key] = fields[key].id;
            } else {
                object[key] = fields[key];
            }
        }
        return object;
    }
    decodeFields(fields, object);
    return object;
}

function parseEnv(arg) {
    switch (arg?.toLowerCase()) {
        case 'localnet':
        case 'devnet':
        case 'testnet':
        case 'mainnet':
            return {alias: arg, url: getFullnodeUrl(arg)};
        default:
            return JSON.parse(arg);
  }
}

module.exports = {
    toPure,
    getModuleNameFromSymbol,
    getConfig,
    setConfig,
    getFullObject,
    parseEnv,
    requestSuiFromFaucet,
};
