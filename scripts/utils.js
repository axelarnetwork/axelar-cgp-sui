const { arrayify } = require('ethers/lib/utils');

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

module.exports = {
    toPure,
    getModuleNameFromSymbol,
}