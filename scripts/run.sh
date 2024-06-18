#!/bin/bash

if [[ ${#} -ne 1 || ( "$1" != "build" && "$1" != "test" ) ]]; then
    echo "Usage: $0 [build|test]"
    exit 1
fi

exit_code=0

for module in ./move/*/; do
    if ! sui move "$1" --lint --warnings-are-errors --path "$module"; then
        exit_code=1
    fi
done

if [ $exit_code -ne 0 ]; then
    echo ""
    echo -e "\033[0;31m$1 failed\033[0m"
    exit 1
fi
