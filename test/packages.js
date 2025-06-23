const fs = require('fs');
const path = require('path');
const chai = require('chai');
const { expect } = chai;
const { execSync } = require('child_process');
const { goldenTest } = require('./testutils');
const toml = require('smol-toml');

describe('Packages', () => {
    const moveDir = path.resolve(__dirname, '../move');

    const packages = fs.readdirSync(moveDir).filter((file) => {
        return fs.statSync(path.join(moveDir, file)).isDirectory();
    });

    packages.forEach((packageName) => {
        describe(`${packageName}`, () => {
            const packageDir = path.join(moveDir, packageName);
            const moveJson = toml.parse(fs.readFileSync(path.join(packageDir, 'Move.toml'), 'utf8'));
            const buildDir = path.join(packageDir, 'build', moveJson.package.name, 'bytecode_modules');

            if (!fs.existsSync(buildDir)) {
                // Build directory does not exist, perhaps package has not been built
                throw new Error(`Build directory ${buildDir} not found for package ${packageName}`);
            }

            const mvFiles = fs.readdirSync(buildDir).filter((file) => {
                return path.extname(file) === '.mv';
            });

            expect(mvFiles.length).to.be.gt(0);

            mvFiles.forEach((mvFile) => {
                const moduleName = path.basename(mvFile, '.mv');

                it(`should match the public interface for module ${moduleName}`, () => {
                    const mvFilePath = path.join(buildDir, mvFile);

                    // Disassemble the compiled Move files to get the public interface
                    let disassembledOutput;

                    try {
                        disassembledOutput = execSync(`sui move disassemble ${mvFilePath}`).toString();
                    } catch (error) {
                        throw new Error(`Failed to disassemble ${mvFilePath}: ${error}`);
                    }

                    const publicInterface = parsePublicInterfaces(disassembledOutput);

                    goldenTest(publicInterface, `interface_${packageName}_${moduleName}`);
                });
            });
        });
    });
});

const structRegex = /^struct (\w+) has (.*) {$/;
const structFieldRegex = /^(\w+): (.*?),?$/;
const publicFunctionRegex = /^public (.+?)\((.*)\): (.*?) {$/;

// Function to parse the disassembled output and extract structs and public functions
function parsePublicInterfaces(disassembledOutput) {
    const lines = disassembledOutput.split('\n');
    const structs = {};
    const publicFunctions = {};

    let currentStruct = null;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();

        // Check for struct definitions
        if (line.startsWith('struct')) {
            const structMatch = line.match(structRegex);

            if (structMatch) {
                currentStruct = {
                    name: structMatch[1],
                    abilities: structMatch[2].trim().split(', '),
                    fields: [],
                };
                structs[currentStruct.name] = currentStruct;
                continue;
            }
        }

        if (currentStruct) {
            // Inside struct definition
            if (line === '}') {
                currentStruct = null;
                continue;
            } else {
                // Parse field
                const fieldMatch = line.match(structFieldRegex);

                if (fieldMatch) {
                    currentStruct.fields.push({
                        name: fieldMatch[1],
                        type: fieldMatch[2],
                    });
                }
            }
        }

        // Check for public function definitions
        if (line.startsWith('public')) {
            const functionMatch = line.match(publicFunctionRegex);

            if (functionMatch) {
                const params = Object.fromEntries(
                    functionMatch[2]
                        .trim()
                        .split(', ')
                        .map((param) => param.split(': ')),
                );

                const currentFunction = {
                    name: functionMatch[1],
                    visibility: 'public',
                    params,
                    returnType: functionMatch[3],
                };
                publicFunctions[currentFunction.name] = currentFunction;
                continue;
            }
        }
    }

    return { structs, publicFunctions };
}
