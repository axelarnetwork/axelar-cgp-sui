const { expect } = require('chai');
const toml = require('smol-toml');
const fs = require('fs');
const path = require('path');
const { updateMoveToml, getLocalDependencies, copyMovePackage } = require('../dist/utils');

describe('Utils', () => {
    describe('updateMoveToml', () => {
        const moveTestDir = `${__dirname}/../move-test`;

        it('should insert published-at and address fields correctly', () => {
            const testPackageName = 'governance';
            const testPackageId = '0x01';

            // Create a new directory for the test package
            copyMovePackage(testPackageName, undefined, moveTestDir);

            // Update the Move.toml file for the test package
            updateMoveToml(testPackageName, testPackageId, moveTestDir);

            const moveToml = toml.parse(fs.readFileSync(`${moveTestDir}/${testPackageName}/Move.toml`, 'utf8'));

            expect(moveToml.package['published-at']).to.equal(testPackageId);
            expect(moveToml.addresses[testPackageName]).to.equal(testPackageId);
        });

        after(async () => {
            fs.rmSync(`${moveTestDir}`, { recursive: true, force: true });
        });
    });

    describe('getLocalDependencies', () => {
        it('should return the correct dependencies', () => {
            const testPackageName = 'governance';
            const baseMoveDir = `${__dirname}/../move`;
            const dependencies = getLocalDependencies(testPackageName, baseMoveDir);

            expect(dependencies.length).to.greaterThan(0);

            for (const dependency of dependencies) {
                const dependencyPath = path.resolve(dependency.path, 'Move.toml');

                // Check if the dependency path exists
                if (fs.existsSync(dependencyPath)) {
                    const dependencyRaw = fs.readFileSync(dependencyPath, 'utf8');

                    const dependencyJson = toml.parse(dependencyRaw);

                    // Check if the dependency name matches the expected name
                    expect(dependencyJson.package.name).to.equal(dependency.name);
                }
            }
        });
    });
});
