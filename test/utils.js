const { expect } = require('chai');
const toml = require('smol-toml');
const fs = require('fs');
const path = require('path');
const { updateMoveToml, getLocalDependencies, copyMovePackage } = require('../dist/cjs');

describe('Utils', () => {
    describe('updateMoveToml', () => {
        const moveTestDir = `${__dirname}/../move-test`;

        it('should update toml and lock files correctly', () => {
            // const chainId = '4c78adac';
            const emptyPackageId = '0x0';
            const testPackageId = '0x0000000000000000000000000000000000000000000000000000000000000001';
            const testPackageName = 'governance';

            // Create a new directory for the test package
            copyMovePackage(testPackageName, undefined, moveTestDir);

            // Build package
            // getContractBuild(testPackageName, moveTestDir);

            // Update the Move.toml file for the test package
            updateMoveToml(testPackageName, testPackageId, moveTestDir);

            const moveToml = toml.parse(fs.readFileSync(`${moveTestDir}/${testPackageName}/Move.toml`, 'utf8'));
            // const moveLock = toml.parse(fs.readFileSync(`${moveTestDir}/${testPackageName}/Move.lock`, 'utf8'));

            expect(moveToml.addresses[testPackageName]).to.equal(emptyPackageId);
            // expect(moveLock.env.testnet['chain-id']).to.equal(chainId);
            // expect(moveLock.env.testnet['original-published-id']).to.equal(testPackageId);
            // expect(moveLock.env.testnet['latest-published-id']).to.equal(testPackageId);
            // expect(moveLock.env.testnet['published-version']).to.equal(String(1));
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
