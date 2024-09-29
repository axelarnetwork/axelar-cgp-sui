#!/bin/bash

./scripts/run.sh build --doc

mkdir -p docs

# Create top-level index.md
echo "# Axelar Sui Move Packages" > docs/index.md
echo "" >> docs/index.md

for dir in move/*/; do
if [ -d "$dir" ]; then
    pkg_name=$(basename "$dir")
    cp -r "$dir"/build/*/docs docs/"$pkg_name"

    # Create index.md for each package
    echo "# Package $pkg_name" > docs/"$pkg_name"/index.md
    echo "" >> docs/"$pkg_name"/index.md

    # Link each module docs in the index.md
    for module in docs/"${pkg_name}"/*.md; do
    if [ -f "$module" ]; then
        module_name=$(basename "$module")
        module_name=${module_name%.md}
        echo "- [$module_name]($pkg_name/$module_name/index.html)" >> docs/"$pkg_name"/index.md
    fi
    done

    echo "- [$pkg_name]($pkg_name/index.html)" >> docs/index.md
fi
done
