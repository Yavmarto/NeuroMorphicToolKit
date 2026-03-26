#!/usr/bin/env bash
set -euo pipefail

# Create DMG installer for NeuroMorphic ToolKit (macOS)
# Usage: ./create-dmg.sh [path-to-app-bundle] [version]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TOOLKIT_DIR="$REPO_ROOT/nmtk/neuro_toolkit"

# Resolve absolute path for app bundle
APP_PATH_INPUT="${1:-$TOOLKIT_DIR/build/macos/Build/Products/Release/neuro_toolkit.app}"
if [[ "$APP_PATH_INPUT" != /* ]]; then
  APP_PATH="$(pwd)/$APP_PATH_INPUT"
else
  APP_PATH="$APP_PATH_INPUT"
fi

VERSION="${2:-dev}"
SIGNING_IDENTITY="${3:-}"
OUTPUT_FILE="NeuroMorphicToolKit-${VERSION}-macos.dmg"
OUTPUT_PATH="$(pwd)/$OUTPUT_FILE"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: App bundle not found at $APP_PATH"
  echo "Run build-standalone.sh first, or 'flutter build macos --release'."
  exit 1
fi

if ! command -v create-dmg &>/dev/null; then
  if ! command -v brew &>/dev/null; then
    echo "Error: 'create-dmg' not found and Homebrew is not installed."
    echo "Please install Homebrew (https://brew.sh) or 'create-dmg' manually."
    exit 1
  fi
  echo "Installing 'create-dmg' via Homebrew..."
  brew install create-dmg
fi

# Create a temporary staging directory
STAGING_DIR="$(mktemp -d -t nmtk-dmg-XXXXXX)"
echo "==> Staging app bundle in $STAGING_DIR..."

# Copy the .app to the staging directory
cp -R "$APP_PATH" "$STAGING_DIR/"

# Remove old DMG if present
rm -f "$OUTPUT_PATH"

echo "==> Building DMG: $OUTPUT_FILE"
create-dmg \
  --volname "NeuroMorphic ToolKit ${VERSION}" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 400 150 \
  --no-internet-enable \
  "$OUTPUT_PATH" \
  "$STAGING_DIR/"

# Cleanup staging directory
rm -rf "$STAGING_DIR"

# Sign DMG if identity provided
if [ -n "$SIGNING_IDENTITY" ]; then
  echo "==> Signing DMG with identity: $SIGNING_IDENTITY..."
  codesign --force --sign "$SIGNING_IDENTITY" "$OUTPUT_PATH"
fi

echo "Created $OUTPUT_FILE ($(du -sh "$OUTPUT_PATH" | awk '{print $1}'))"
