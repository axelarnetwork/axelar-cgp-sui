const { expect } = require('chai');
const toml = require('smol-toml');
const fs = require('fs');
const { updateMoveToml, copyMovePackage } = require('../dist/utils');

describe('UpdateMoveToml', () => {
    const moveTestDir = `${__dirname}/../move-test`;

    it('should insert published-at and address fields correctly', () => {
        const testPackageName = 'governance';
        const testPackageId = '0x01';

        // Create a new directory for the test package
        copyMovePackage(testPackageName, undefined, moveTestDir);

        // Update the Move.toml file for the test package
        updateMoveToml(testPackageName, testPackageId, moveTestDir);

        const moveToml = toml.parse(fs.readFileSync(`${moveTestDir}/${testPackageName}/Move.toml`, 'utf8'));

        expect(moveToml.package.published_at).to.equal(testPackageId);
        expect(moveToml.addresses[testPackageName]).to.equal(testPackageId);
    });
});
