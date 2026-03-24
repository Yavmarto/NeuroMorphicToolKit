#!/bin/bash
# CDD-PBT Validation Script for Agents
# Run this from the root of the repository to validate a module.

if [ -z "$1" ]; then
    echo "Usage: $0 <module_directory>"
    echo "Example: $0 Neurosim"
    exit 1
fi

MODULE_DIR=$1

echo "============================================="
echo "Running CDD-PBT Validation for: $MODULE_DIR"
echo "============================================="

if [ ! -d "$MODULE_DIR" ]; then
    echo "❌ Error: Directory $MODULE_DIR not found."
    exit 1
fi

cd "$MODULE_DIR" || exit 1

# Detect Python/Poetry or Flutter
if [ -f "pyproject.toml" ]; then
    echo "🔄 Detected Poetry project."
    poetry run pytest --tb=short --hypothesis-show-statistics
    EXIT_CODE=$?
elif [ -f "requirements.txt" ] || [ -f "setup.py" ] || [ -f "setup.cfg" ]; then
    echo "🔄 Detected standard Python project."
    pytest --tb=short --hypothesis-show-statistics
    EXIT_CODE=$?
elif [ -f "pubspec.yaml" ]; then
    echo "🔄 Detected Flutter/Dart project."
    flutter test
    EXIT_CODE=$?
else
    echo "⚠️ Unknown project type. Trying standard pytest..."
    pytest --tb=short --hypothesis-show-statistics
    EXIT_CODE=$?
fi

echo "============================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ CDD-PBT Validation PASSED for $MODULE_DIR."
    exit 0
else
    echo "❌ CDD-PBT Validation FAILED. Contracts or Properties were violated."
    exit $EXIT_CODE
fi
