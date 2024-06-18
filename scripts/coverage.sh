#!/bin/sh

export SUI=sui-debug

# Check if sui-debug is available
if ! which "$SUI" >/dev/null 2>&1; then
  echo "sui-debug not found. Setting SUI to ./sui/target/debug/sui."

  # Default to a local Sui build
  export SUI="./sui/target/debug/sui"

  # Check if the file exists, install it otherwise
  if [ ! -f "$SUI" ]; then
    echo "Warning: $SUI not found. Installing sui-debug from scratch."

    git clone https://github.com/MystenLabs/sui.git
    ( cd sui && cargo build )
    ./sui/target/debug/sui version
  fi
fi

for module in ./move/*/; do
    "$SUI" move test --path "$module" --coverage &
done

wait

found=0

for module in ./move/*/; do
    echo "Generating coverage info for package ${module}"

    if [ ! -f "${module}/.coverage_map.mvcov" ]; then
        echo "\n NO tests found for module ${module}. Skipped.\n" >> .coverage.info
        echo "\n NO tests found for module ${module}. Skipped.\n" >> .coverage.extended.info
        continue
    fi

    found=1

    echo "Coverage report for module ${module}\n" >> .coverage.info
    echo "Coverage report for module ${module}\n" >> .coverage.extended.info

    "$SUI" move coverage summary --path "${module}" >> .coverage.info
    "$SUI" move coverage summary --summarize-functions --path "${module}" >> .coverage.extended.info

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
