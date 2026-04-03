#!/bin/bash
set -e

# List of Python submodules/packages
PYTHON_DIRS=("Neuro-Dream-Hand" "neurocnl" "Neurosense" "Neurohub" "Neurochip/neurochip" "Neurobench/neurobench" "Neurosim/neurosim")

ROOT_DIR=$(pwd)
EXIT_CODE=0

# Irrelevant folders to exclude from mypy
EXCLUDE_PATTERN="(build|dist|venv|\.venv|frontend|docs|.*\.egg-info|__pycache__|\.mypy_cache|\.pytest_cache|\.tox|\.nox)"

for dir in "${PYTHON_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Running mypy in $dir..."
        cd "$dir"
        
        if ! mypy . --exclude "$EXCLUDE_PATTERN"; then
            echo "Mypy failed in $dir"
            EXIT_CODE=1
        fi
        cd "$ROOT_DIR"
    else
        echo "Directory $dir not found, skipping..."
    fi
done

exit $EXIT_CODE
