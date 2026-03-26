#!/usr/bin/env bash
set -euo pipefail

# Create AppImage for NMTK Launcher (Linux)
# Usage: ./appimage.sh [version]

VERSION="${1:-1.0.0}"
BUNDLE_DIR="nmtk/neuro_toolkit/build/linux/x64/release/bundle"
APPDIR="NMTK-Launcher.AppDir"
OUTPUT="NMTK-Launcher-${VERSION}-x86_64.AppImage"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ ! -d "$REPO_ROOT/${BUNDLE_DIR}" ]; then
  echo "Error: Flutter bundle not found at ${BUNDLE_DIR}"
  echo "Run 'flutter build linux --release' first."
  exit 1
fi

# Create AppDir structure
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin/modules" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy Flutter bundle
cp -r "$REPO_ROOT/${BUNDLE_DIR}"/* "$APPDIR/usr/bin/"

# Bundle all 7 submodules
echo "📦 Bundling submodules..."
MODULES=("neurocnl" "Neurosim" "Neurochip" "Neurobench" "Neurosense" "Neurohub" "Neuro-Dream-Hand")

for mod in "${MODULES[@]}"; do
  if [ -d "$REPO_ROOT/$mod" ]; then
    echo "  - Bundling $mod"
    rsync -a --exclude='.git' --exclude='venv' --exclude='build' --exclude='__pycache__' \
      "$REPO_ROOT/$mod/" "$APPDIR/usr/bin/modules/$mod/"
  else
    echo "  ⚠️ Warning: Module $mod not found at $REPO_ROOT/$mod"
  fi
done

# Copy desktop file and AppRun
cp "$SCRIPT_DIR/nmtk.desktop" "$APPDIR/"
cp "$SCRIPT_DIR/AppRun" "$APPDIR/"
chmod +x "$APPDIR/AppRun"

# Copy icons
# Using neuro_toolkit assets if available, or fallback to neurocnl icon for now
ICON_SRC="$REPO_ROOT/nmtk/neuro_toolkit/linux/runner/resources/app_icon.png"
if [ ! -f "$ICON_SRC" ]; then
  # Fallback to the one used in the previous version if it exists
  ICON_SRC="$REPO_ROOT/neurocnl/frontend/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png"
fi

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
# rm -rf "$APPDIR"
