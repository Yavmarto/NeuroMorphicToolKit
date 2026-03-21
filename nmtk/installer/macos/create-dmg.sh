#!/usr/bin/env bash
set -euo pipefail

# Create DMG installer for NeuroMorphic ToolKit (macOS)
# Usage: ./create-dmg.sh [path-to-app-bundle] [version]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TOOLKIT_DIR="$REPO_ROOT/nmtk/neuro_toolkit"

APP_PATH="${1:-$TOOLKIT_DIR/build/macos/Build/Products/Release/neuro_toolkit.app}"
VERSION="${2:-dev}"
OUTPUT="NeuroMorphicToolKit-${VERSION}-macos.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: App bundle not found at $APP_PATH"
  echo "Run build-standalone.sh first, or 'flutter build macos --release'."
  exit 1
fi

if ! command -v create-dmg &>/dev/null; then
  echo "Installing create-dmg..."
  brew install create-dmg
fi

# Remove old DMG if present (create-dmg fails if output exists)
rm -f "$OUTPUT"

create-dmg \
  --volname "NeuroMorphic ToolKit ${VERSION}" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 400 150 \
  --no-internet-enable \
  "$OUTPUT" \
  "$APP_PATH"

echo "Created $OUTPUT ($(du -sh "$OUTPUT" | awk '{print $1}'))"
