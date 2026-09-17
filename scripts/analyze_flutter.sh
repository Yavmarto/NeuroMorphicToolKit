#!/bin/bash
set -e

# Get the root directory
ROOT_DIR=$(git rev-parse --show-toplevel)

# Find all directories with pubspec.yaml
FLUTTER_DIRS=$(find "$ROOT_DIR" -name "pubspec.yaml" -not -path "*/.dart_tool/*" -not -path "*/venv/*" -not -path "*/.venv/*" -exec dirname {} \;)

EXIT_CODE=0

for dir in $FLUTTER_DIRS; do
    echo "Analyzing Flutter package in $dir..."
    cd "$dir"
    if ! flutter analyze; then
        echo "Analysis failed in $dir"
        EXIT_CODE=1
    fi
    cd "$ROOT_DIR"
done

exit $EXIT_CODE
