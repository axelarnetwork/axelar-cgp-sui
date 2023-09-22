const { arrayify } = require('ethers/lib/utils');

function toPure(hexString) {
    return String.fromCharCode(...arrayify(hexString));
}

module.exports = {
    toPure,
}