const fs = require('fs');
const path = require('path');

function checkForNodeImports(dir) {
    const files = fs.readdirSync(dir);
    const nodePatterns = ['node-utils', 'require(', 'fs.', 'path.', '__dirname', '__filename'];

    files.forEach((file) => {
        const filePath = path.join(dir, file);

        if (fs.statSync(filePath).isDirectory()) {
            checkForNodeImports(filePath);
        } else if (file.endsWith('.js')) {
            const content = fs.readFileSync(filePath, 'utf8');
            nodePatterns.forEach((pattern) => {
                if (content.includes(pattern)) {
                    console.error(`Found node-specific code in ${filePath}: ${pattern}`);
                    process.exit(1);
                }
            });
        }
    });
}

const webDist = path.join(__dirname, '../dist/web');
checkForNodeImports(webDist);
console.log('Web build is clean of node-specific code');
