const { expect } = require('chai');
const toml = require('smol-toml');
const fs = require('fs');
const path = require('path');
const { updateMoveToml, getLocalDependencies, copyMovePackage } = require('../dist/cjs');

describe('Utils', () => {
    // TODO: make contract building work for tests to test lock files
    describe('updateMoveToml', () => {
        const moveTestDir = `${__dirname}/../move-test`;

        it('should update addresses in Move.toml correctly', () => {
            const testPackageId = '0x01';
            const testPackageName = 'governance';

            // Create a new directory for the test package
            copyMovePackage(testPackageName, undefined, moveTestDir);

            // Update the Move.toml file for the test package
            updateMoveToml(testPackageName, testPackageId, moveTestDir);

            const moveToml = toml.parse(fs.readFileSync(`${moveTestDir}/${testPackageName}/Move.toml`, 'utf8'));

            // Unpublished builds use package id (this avoids dependency collisions)
            // published builds reset addresses to '0x0'
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
