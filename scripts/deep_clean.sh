#!/bin/bash

# Deep Clean Script - NeuroMorphicToolKit
# Removes all virtual environments, Flutter build artifacts, and Python caches.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

echo "Starting deep clean in: $REPO_ROOT"

# 1. Remove Python Virtual Environments
echo "Removing virtual environments (.venv, venv)..."
find . -name ".venv" -type d -prune -exec rm -rf {} +
find . -name "venv" -type d -prune -exec rm -rf {} +

# 2. Remove Flutter Build Artifacts
echo "Removing Flutter build artifacts (build, .dart_tool, ephemeral)..."
find . -name "build" -type d -prune -exec rm -rf {} +
find . -name ".dart_tool" -type d -prune -exec rm -rf {} +
find . -name "ephemeral" -type d -prune -exec rm -rf {} +

# 3. Remove Python Caches
echo "Removing Python caches (__pycache__, .pyc)..."
find . -name "__pycache__" -type d -prune -exec rm -rf {} +
find . -name "*.pyc" -type f -delete

# 4. Cleanup Poetry locks
if command -v poetry &> /dev/null; then
    echo "Clearing poetry locks..."
    find . -name "poetry.lock" -type f -delete
fi

echo "----------------------------------------"
echo "DEEP CLEAN COMPLETE."
echo "----------------------------------------"
echo "Next steps:"
echo "1. Create root virtual env: python3 -m venv .venv && source .venv/bin/activate"
echo "2. Install shared libs: cd neurocnl && pip install -e .[dev] && cd ../Neuro-Dream-Hand && pip install -e .[dev] && cd .."
echo "3. Build submodules: make build-submodules"
echo "4. Launch launcher: make dev"
