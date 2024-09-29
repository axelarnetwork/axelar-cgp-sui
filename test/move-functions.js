const { expect } = require('chai');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

describe.only('Move public schema', () => {
    const moveDir = path.resolve(__dirname, '../move');
    const goldenDir = path.resolve(__dirname, '../golden');

    // Get the list of Move packages under move/
    const packages = fs.readdirSync(moveDir).filter((file) => {
        return fs.statSync(path.join(moveDir, file)).isDirectory();
    });

    packages.forEach((packageName) => {
        describe(`Package: ${packageName}`, () => {
            const packageDir = path.join(moveDir, packageName);

            // Path to .mv files under build/<package_name>/bytecode_modules/
            const buildDir = path.join(packageDir, 'build', packageName.replace('_', ''), 'bytecode_modules');

            if (!fs.existsSync(buildDir)) {
                // Build directory does not exist, perhaps package has not been built
                console.warn(`Build directory not found for package ${packageName}, skipping`);
                return;
            }

            const mvFiles = fs.readdirSync(buildDir).filter((file) => {
                return path.extname(file) === '.mv';
            });

            mvFiles.forEach((mvFile) => {
                it(`should match the golden file for module ${mvFile}`, () => {
                    const mvFilePath = path.join(buildDir, mvFile);

                    // Disassemble the .mv file using `sui move disassemble path_to_mv`
                    const disassembleCmd = `sui move disassemble ${mvFilePath}`;
                    let disassembledOutput;
                    try {
                        disassembledOutput = execSync(disassembleCmd).toString();
                    } catch (error) {
                        throw new Error(`Failed to disassemble ${mvFilePath}: ${error}`);
                    }

                    // Parse the disassembled output to extract structs and public functions
                    const extractedInfo = parseDisassembledOutput(disassembledOutput);

                    // Generate JSON representation
                    const extractedJson = JSON.stringify(extractedInfo, null, 2);

                    const moduleName = path.basename(mvFile, '.mv');
                    const goldenFilePath = path.join(goldenDir, packageName, `${moduleName}.json`);

                    if (process.env.GOLDEN_TESTS) {
                        // Write the extracted info to the golden file
                        fs.mkdirSync(path.dirname(goldenFilePath), { recursive: true });
                        fs.writeFileSync(goldenFilePath, extractedJson);
                    } else {
                        // Read the golden file and compare
                        if (!fs.existsSync(goldenFilePath)) {
                            throw new Error(`Golden file not found: ${goldenFilePath}`);
                        }

                        const goldenJson = fs.readFileSync(goldenFilePath, 'utf8');

                        expect(extractedJson).to.equal(goldenJson, `Module ${moduleName} has changed structs or public functions`);
                    }
                });
            });
        });
    });
});

// Function to parse the disassembled output and extract structs and public functions
function parseDisassembledOutput(disassembledOutput) {
    const lines = disassembledOutput.split('\n');
    const structs = {};
    const publicFunctions = {};

    let currentStruct = null;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();

        // Check for struct definitions
        if (line.startsWith('struct')) {
            const structMatch = line.match(/^struct (\w+) has (.*) {$/);
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
                const fieldMatch = line.match(/^(\w+): (.*),?$/);
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
            const functionMatch = line.match(/^public (.+?)\((.*)\): (.*?) {$/);
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
