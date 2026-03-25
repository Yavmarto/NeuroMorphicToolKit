#!/usr/bin/env bash
set -euo pipefail

# Create AppImage for NeuroMorphic ToolKit (Linux)
# Usage: ./appimage.sh [version]

VERSION="${1:-dev}"
BUNDLE_DIR="nmtk/neuro_toolkit/build/linux/x64/release/bundle"
APPDIR="NeuroMorphicToolKit.AppDir"
OUTPUT="NeuroMorphicToolKit-${VERSION}-x86_64.AppImage"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ ! -d "$REPO_ROOT/${BUNDLE_DIR}" ]; then
  echo "Error: Flutter bundle not found at ${BUNDLE_DIR}"
  echo "Run 'flutter build linux --release' first."
  exit 1
fi

# Create AppDir structure
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy Flutter bundle
cp -r "$REPO_ROOT/${BUNDLE_DIR}"/* "$APPDIR/usr/bin/"

# Copy modules
MODULES_DIR="$APPDIR/usr/bin/modules"
mkdir -p "$MODULES_DIR"
MODULES=(neurocnl Neurosim Neurochip Neurobench Neurosense Neurohub Neuro-Dream-Hand)

for mod in "${MODULES[@]}"; do
  SRC="$REPO_ROOT/$mod"
  DEST="$MODULES_DIR/$mod"

  if [ ! -d "$SRC" ]; then
    echo "  Warning: $SRC not found, skipping"
    continue
  fi

  echo "  Copying $mod..."
  rsync -a \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='venv' \
    --exclude='node_modules' \
    --exclude='.dart_tool' \
    --exclude='build' \
    --exclude='.flutter-plugins*' \
    --exclude='*.egg-info' \
    --exclude='.mypy_cache' \
    --exclude='.ruff_cache' \
    --exclude='.pytest_cache' \
    --exclude='frontend/build' \
    --exclude='frontend/.dart_tool' \
    "$SRC/" "$DEST/"
done

# Copy desktop file and AppRun
cp "$SCRIPT_DIR/nmtk.desktop" "$APPDIR/"
cp "$SCRIPT_DIR/AppRun" "$APPDIR/"
chmod +x "$APPDIR/AppRun"

# Copy icons
ICON_SRC="$REPO_ROOT/nmtk/neuro_toolkit/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APPDIR/nmtk.png"
  cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/nmtk.png"
fi

# Download appimagetool if not present
if [ ! -f appimagetool-x86_64.AppImage ]; then
  wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x appimagetool-x86_64.AppImage
fi

# Set environment for running in Docker/CI without FUSE
export APPIMAGE_EXTRACT_AND_RUN=1

ARCH=x86_64 ./appimagetool-x86_64.AppImage "$APPDIR" "$OUTPUT"
echo "✅ Created $OUTPUT"

# Cleanup
rm -rf "$APPDIR"
