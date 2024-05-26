#!/bin/sh

export SUI=sui-debug

# Check if sui-debug is available
if ! which "$SUI" >/dev/null 2>&1; then
  echo "sui-debug not found. Setting SUI to ./sui/target/debug/sui."

  # Default to a local Sui build
  export SUI="./sui/target/debug/sui"

  # Check if the file exists
  if [ ! -f "$SUI" ]; then
    echo "Error: $SUI not found. Exiting."
    exit 1
  fi
fi

for d in ./move/*/; do
    "$SUI" move test --path "$d" --coverage &
done

wait

found=0

for d in ./move/*/; do
    echo "Generating coverage info for package $d"

    if [ ! -f "$d/.coverage_map.mvcov" ]; then
        echo "\n NO tests found for module $d. Skipped.\n" >> .coverage.info
        echo "\n NO tests found for module $d. Skipped.\n" >> .coverage.extended.info
        continue
    fi

    found=1

    echo "Coverage report for module $d\n" >> .coverage.info
    echo "Coverage report for module $d\n" >> .coverage.extended.info

    "$SUI" move coverage summary --path "$d" >> .coverage.info
    "$SUI" move coverage summary --summarize-functions --path "$d" >> .coverage.extended.info

    echo "" >> .coverage.info
    echo "" >> .coverage.extended.info

    # Display source code with coverage info
    # find "$d/sources" -type f -name '*.move' | while IFS= read -r f; do
    #     "$SUI" move coverage source --path "$d" --module "$(basename "$f" .move)"
    # done
done

if [ $found -eq 0 ]; then
    echo "No coverage info found. Coverage failed."
    exit 1
fi
