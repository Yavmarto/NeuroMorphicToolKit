#!/usr/bin/env bash
# release.sh — Release automation pipeline for NMTK.
# Usage: ./release.sh <version>
#   version — semantic version (e.g., 1.0.0)

set -euo pipefail

VERSION="$1"
# Basic semver regex check
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "Error: Version '$VERSION' is not a valid semantic version (x.y.z)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Starting NMTK Release Pipeline for version $VERSION"
echo "──────────────────────────────────────────────────────"

# 1. Update versions in submodules
echo "📦 Updating versions and changelogs in submodules..."

MODULES=("neurocnl" "Neuro-Dream-Hand" "Neurobench" "Neurosim" "Neurosense" "Neurochip" "Neurohub")

for mod in "${MODULES[@]}"; do
  if [ -d "$ROOT_DIR/$mod" ]; then
    echo "  → Processing $mod..."
    cd "$ROOT_DIR/$mod"

    # Identify version files
    VERSION_FILES=()
    if [ -f "pyproject.toml" ]; then VERSION_FILES+=("pyproject.toml"); fi
    if [ -f "neurochip/pyproject.toml" ]; then VERSION_FILES+=("neurochip/pyproject.toml"); fi
    if [ -f "neurobench/pyproject.toml" ]; then VERSION_FILES+=("neurobench/pyproject.toml"); fi
    if [ -f "neurosense/pyproject.toml" ]; then VERSION_FILES+=("neurosense/pyproject.toml"); fi
    if [ -f "frontend/pubspec.yaml" ]; then VERSION_FILES+=("frontend/pubspec.yaml"); fi
    if [ -f "nmtk_ui_core/pubspec.yaml" ]; then VERSION_FILES+=("nmtk_ui_core/pubspec.yaml"); fi

    # Bump version
    if [ ${#VERSION_FILES[@]} -gt 0 ]; then
       python3 "$SCRIPT_DIR/bump_version.py" "$VERSION" "${VERSION_FILES[@]}"
    fi

    # Generate changelog
    python3 "$SCRIPT_DIR/generate_changelog.py" "$VERSION" "."

    # Commit and tag
    git add -A
    # Only commit if there are changes
    if ! git diff --cached --quiet; then
        git commit -m "chore(release): $VERSION"
        git tag -a "v$VERSION" -m "Release $VERSION"
        echo "  ✓ Tagged $mod as v$VERSION"
    else
        echo "  ⚠ No changes in $mod, skipping tag (or tag manually if needed)."
    fi
  fi
done

# 2. Update versions in core components
echo "──────────────────────────────────────────────────────"
echo "📦 Updating core components..."

CORE_FILES=("$ROOT_DIR/nmtk/neuro_toolkit/pubspec.yaml" "$ROOT_DIR/nmtk_ui_core/pubspec.yaml")
python3 "$SCRIPT_DIR/bump_version.py" "$VERSION" "${CORE_FILES[@]}"

# 3. Update root repo
echo "──────────────────────────────────────────────────────"
echo "🌳 Updating root repository..."
cd "$ROOT_DIR"

python3 "$SCRIPT_DIR/generate_changelog.py" "$VERSION" "."

# Stage submodule pointers and other changes
git add -A
if ! git diff --cached --quiet; then
    git commit -m "chore(release): v$VERSION"
    git tag -a "v$VERSION" -m "Release $VERSION"
    echo "✓ Root repository tagged as v$VERSION"
else
    echo "⚠ No changes in root repo, skipping tag."
fi

echo "──────────────────────────────────────────────────────"
echo "✅ Release $VERSION ready locally."
echo "   Run 'git push origin main --tags' to trigger CI release pipelines."
