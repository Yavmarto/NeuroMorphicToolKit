#!/usr/bin/env bash
set -euo pipefail

# Create AppImage for NeuroCNL Studio (Linux)
# Usage: ./appimage.sh [version]

VERSION="${1:-dev}"
BUNDLE_DIR="neurocnl/frontend/build/linux/x64/release/bundle"
APPDIR="NeuroCNL-Studio.AppDir"
OUTPUT="NeuroCNL-Studio-${VERSION}-x86_64.AppImage"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "../../${BUNDLE_DIR}" ]; then
  echo "Error: Flutter bundle not found at ${BUNDLE_DIR}"
  echo "Run 'flutter build linux --release' first."
  exit 1
fi

# Create AppDir structure
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy Flutter bundle
cp -r "../../${BUNDLE_DIR}"/* "$APPDIR/usr/bin/"

# Copy desktop file and AppRun
cp "$SCRIPT_DIR/neurocnl-studio.desktop" "$APPDIR/"
cp "$SCRIPT_DIR/AppRun" "$APPDIR/"
chmod +x "$APPDIR/AppRun"

# Download appimagetool if not present
if [ ! -f appimagetool-x86_64.AppImage ]; then
  wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x appimagetool-x86_64.AppImage
fi

ARCH=x86_64 ./appimagetool-x86_64.AppImage "$APPDIR" "$OUTPUT"
echo "✅ Created $OUTPUT"

# Cleanup
rm -rf "$APPDIR"
