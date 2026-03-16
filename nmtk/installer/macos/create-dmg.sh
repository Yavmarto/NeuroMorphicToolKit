#!/usr/bin/env bash
set -euo pipefail

# Create DMG installer for NeuroCNL Studio (macOS)
# Usage: ./create-dmg.sh [path-to-app-bundle] [version]

APP_PATH="${1:-build/macos/Build/Products/Release/neurocnl_studio.app}"
VERSION="${2:-dev}"
OUTPUT="neurocnl-studio-${VERSION}-macos.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: App bundle not found at $APP_PATH"
  echo "Run 'flutter build macos --release' first."
  exit 1
fi

if ! command -v create-dmg &>/dev/null; then
  echo "Installing create-dmg..."
  brew install create-dmg
fi

create-dmg \
  --volname "NeuroCNL Studio ${VERSION}" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 400 150 \
  --no-internet-enable \
  "$OUTPUT" \
  "$APP_PATH"

echo "✅ Created $OUTPUT"
