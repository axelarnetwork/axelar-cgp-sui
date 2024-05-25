#!/bin/sh

export SUI=sui-debug

# Check if sui-debug is available
if ! type "$SUI" >/dev/null 2>&1; then
  echo "sui-debug not found. Setting SUI to ./sui/target/debug/sui."

  # Default to a local Sui build
  export SUI="./sui/target/debug/sui"

  # Check if the file exists
  if [ ! -f "$SUI" ]; then
    echo "Error: $SUI not found. Exiting."
    exit 1
  fi
fi

echo 'Axelar Move Coverage Report' > .coverage.info
echo '' >> .coverage.info

for d in ./move/*/; do
    "$SUI" move test --path "$d" --coverage

    if [ ! -f "$d/.coverage_map.mvcov" ]; then
        echo "\n NO tests found for module $d. Skipped.\n" >> .coverage.info
        continue
    fi

    echo "\nCoverage report for module $d\n" >> .coverage.info

    "$SUI" move coverage summary --path "$d" >> .coverage.info
done
