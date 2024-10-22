const fs = require('fs');
const path = require('path');

function updateImportPaths(content) {
    // Update relative imports from ../common/ or ../node/ to ./
    content = content.replace(/require\("\.\.\/common\/(.*?)"\)/g, 'require("./$1")');
    content = content.replace(/require\("\.\.\/node\/(.*?)"\)/g, 'require("./$1")');
    content = content.replace(/require\("\.\.\/web\/(.*?)"\)/g, 'require("./$1")');
    
    // Update import statements for .js files
    content = content.replace(/from\s+['"]\.\.\/common\/(.*?)['"]/g, 'from "./$1"');
    content = content.replace(/from\s+['"]\.\.\/node\/(.*?)['"]/g, 'from "./$1"');
    content = content.replace(/from\s+['"]\.\.\/web\/(.*?)['"]/g, 'from "./$1"');

    // Update references in .d.ts files
    content = content.replace(/from\s+['"]\.\.\/common\/(.*?)['"]/g, 'from "./$1"');
    content = content.replace(/from\s+['"]\.\.\/node\/(.*?)['"]/g, 'from "./$1"');
    content = content.replace(/from\s+['"]\.\.\/web\/(.*?)['"]/g, 'from "./$1"');

    return content;
}

function flattenAndUpdateDirectory(dir) {
    const items = fs.readdirSync(dir, { withFileTypes: true });
    
    // First, process all directories
    for (const item of items) {
        if (item.isDirectory()) {
            const subDir = path.join(dir, item.name);
            const subItems = fs.readdirSync(subDir);
            
            // Move and update each file
            for (const subItem of subItems) {
                const oldPath = path.join(subDir, subItem);
                const newPath = path.join(dir, subItem);
                
                // Read and update content
                let content = fs.readFileSync(oldPath, 'utf8');
                content = updateImportPaths(content);
                
                // Write to new location
                fs.writeFileSync(newPath, content);
                fs.unlinkSync(oldPath);
            }
            
            // Remove empty directory
            fs.rmdirSync(subDir);
        }
    }

    // Then, update files in the root directory
    const rootFiles = fs.readdirSync(dir, { withFileTypes: true });

    for (const file of rootFiles) {
        if (file.isFile()) {
            const filePath = path.join(dir, file.name);
            let content = fs.readFileSync(filePath, 'utf8');
            content = updateImportPaths(content);
            fs.writeFileSync(filePath, content);
        }
    }
}

function processBuild(distDir) {
    if (!fs.existsSync(distDir)) {
        console.error(`Directory ${distDir} does not exist`);
        process.exit(1);
    }

    flattenAndUpdateDirectory(distDir);
}

// If script is run directly
if (require.main === module) {
    const distDir = process.argv[2];

    if (!distDir) {
        console.error('Please provide the dist directory path');
        process.exit(1);
    }

    processBuild(distDir);
}

module.exports = { processBuild };
