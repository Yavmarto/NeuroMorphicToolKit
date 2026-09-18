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
MODULES=("neurocnl" "Neurochip" "Neurobench" "Neurosense" "Neurohub" "Neuro-Dream-Hand")

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

# Copy icons — appimagetool requires Icon= from the .desktop file to exist in AppDir.
ICON_CANDIDATES=(
  "$REPO_ROOT/nmtk/neuro_toolkit/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png"
  "$REPO_ROOT/nmtk/neuro_toolkit/web/icons/Icon-512.png"
  "$REPO_ROOT/nmtk/neuro_toolkit/linux/runner/resources/app_icon.png"
)
ICON_SRC=""
for candidate in "${ICON_CANDIDATES[@]}"; do
  if [ -f "$candidate" ]; then
    ICON_SRC="$candidate"
    break
  fi
done
if [ -z "$ICON_SRC" ]; then
  echo "Error: no launcher icon found (checked: ${ICON_CANDIDATES[*]})" >&2
  exit 1
fi
cp "$ICON_SRC" "$APPDIR/nmtk.png"
cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/nmtk.png"

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
