#!/bin/bash
set -e

# List of Python submodules/packages
PYTHON_DIRS=("Neuro-Dream-Hand" "neurocnl" "Neurosense" "Neurohub" "Neurochip/neurochip" "Neurobench/neurobench" "Neurosim/neurosim")

ROOT_DIR=$(pwd)
EXIT_CODE=0

for dir in "${PYTHON_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Running mypy in $dir..."
        cd "$dir"
        if ! mypy .; then
            echo "Mypy failed in $dir"
            EXIT_CODE=1
        fi
        cd "$ROOT_DIR"
    else
        echo "Directory $dir not found, skipping..."
    fi
done

exit $EXIT_CODE
