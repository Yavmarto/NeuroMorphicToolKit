#!/usr/bin/env bash
set -euo pipefail

# Build a self-contained NeuroMorphicToolKit .app for macOS.
#
# This script:
#   1. Downloads a standalone Python interpreter (python-build-standalone)
#   2. Builds the Flutter desktop app
#   3. Bundles Python + all module source code into the .app
#   4. Ad-hoc code signs the bundle
#   5. Optionally creates a DMG
#
# Usage: ./build-standalone.sh [--skip-flutter] [--dmg]
#
# Prerequisites: Flutter SDK, internet access (for Python download)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TOOLKIT_DIR="$REPO_ROOT/nmtk/neuro_toolkit"

# Python version to bundle
PYTHON_VERSION="3.12.7"
PYTHON_RELEASE="20241016"
# Extracts major.minor (e.g., 3.12)
PYTHON_MAJ_MIN=$(echo "$PYTHON_VERSION" | cut -d. -f1,2)

SKIP_FLUTTER=false
CREATE_DMG=false

for arg in "$@"; do
  case $arg in
    --skip-flutter) SKIP_FLUTTER=true ;;
    --dmg) CREATE_DMG=true ;;
  esac
done

# --- Detect architecture ---
ARCH="$(uname -m)"
case "$ARCH" in
  arm64)  PYTHON_ARCH="aarch64" ;;
  x86_64) PYTHON_ARCH="x86_64" ;;
  *)
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "==> Building for $ARCH (Python arch: $PYTHON_ARCH)"

# --- Download standalone Python ---
PYTHON_TARBALL="cpython-${PYTHON_VERSION}+${PYTHON_RELEASE}-${PYTHON_ARCH}-apple-darwin-install_only.tar.gz"
PYTHON_URL="https://github.com/indygreg/python-build-standalone/releases/download/${PYTHON_RELEASE}/${PYTHON_TARBALL}"
PYTHON_CACHE_DIR="$REPO_ROOT/.cache/python-standalone"
PYTHON_CACHE="$PYTHON_CACHE_DIR/$PYTHON_TARBALL"
PYTHON_EXTRACT_DIR="$PYTHON_CACHE_DIR/python-$PYTHON_ARCH"

if [ ! -d "$PYTHON_EXTRACT_DIR" ]; then
  echo "==> Downloading standalone Python ${PYTHON_VERSION} for ${PYTHON_ARCH}..."
  mkdir -p "$PYTHON_CACHE_DIR"
  if [ ! -f "$PYTHON_CACHE" ]; then
    curl -L -o "$PYTHON_CACHE" "$PYTHON_URL"
  fi
  echo "==> Extracting Python..."
  mkdir -p "$PYTHON_EXTRACT_DIR"
  tar -xzf "$PYTHON_CACHE" -C "$PYTHON_EXTRACT_DIR"
  echo "==> Python extracted to $PYTHON_EXTRACT_DIR"
else
  echo "==> Using cached Python at $PYTHON_EXTRACT_DIR"
fi

# Locate the python root inside the extracted dir (usually python/)
PYTHON_ROOT="$PYTHON_EXTRACT_DIR/python"
if [ ! -f "$PYTHON_ROOT/bin/python3" ]; then
  echo "Error: Python binary not found at $PYTHON_ROOT/bin/python3"
  echo "Contents of extract dir:"
  ls -la "$PYTHON_EXTRACT_DIR"
  exit 1
fi

# --- Clean previous bundled content from build output ---
# Flutter's code signing step will fail if it finds non-standard
# content (like a bundled Python) inside an existing .app from a
# previous build. Remove it before building.
PREV_APP="$TOOLKIT_DIR/build/macos/Build/Products/Release/neuro_toolkit.app"
if [ -d "$PREV_APP/Contents/Frameworks/python" ]; then
  echo "==> Cleaning previous bundled Python from build output..."
  rm -rf "$PREV_APP/Contents/Frameworks/python"
fi
if [ -d "$PREV_APP/Contents/Resources/modules" ]; then
  echo "==> Cleaning previous bundled modules from build output..."
  rm -rf "$PREV_APP/Contents/Resources/modules"
fi

# --- Build Flutter app ---
if [ "$SKIP_FLUTTER" = false ]; then
  echo "==> Building Flutter macOS app..."
  cd "$TOOLKIT_DIR"
  flutter pub get
  flutter build macos --release
  cd "$REPO_ROOT"
else
  echo "==> Skipping Flutter build (--skip-flutter)"
fi

APP_PATH="$TOOLKIT_DIR/build/macos/Build/Products/Release/neuro_toolkit.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Error: App bundle not found at $APP_PATH"
  echo "Run without --skip-flutter or build manually first."
  exit 1
fi

# Resolve absolute path for APP_PATH
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"

echo "==> App bundle: $APP_PATH"

# --- Bundle Python into .app ---
echo "==> Bundling Python into .app..."
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks/python"
rm -rf "$FRAMEWORKS_DIR"
mkdir -p "$FRAMEWORKS_DIR"
cp -R "$PYTHON_ROOT"/* "$FRAMEWORKS_DIR/"

# Slim down Python: remove test suites, idle, tkinter, Tcl/Tk to save space.
# NOTE: Do NOT remove ensurepip or its bundled .whl files — they are needed
# for `python -m venv` to bootstrap pip inside virtual environments.
echo "==> Trimming Python bundle (using version $PYTHON_MAJ_MIN)..."
rm -rf "$FRAMEWORKS_DIR/lib/python${PYTHON_MAJ_MIN}/test" \
       "$FRAMEWORKS_DIR/lib/python${PYTHON_MAJ_MIN}/idlelib" \
       "$FRAMEWORKS_DIR/lib/python${PYTHON_MAJ_MIN}/tkinter" \
       "$FRAMEWORKS_DIR/lib/python${PYTHON_MAJ_MIN}/turtledemo" \
       "$FRAMEWORKS_DIR/lib/tk"* \
       "$FRAMEWORKS_DIR/lib/tcl"* \
       "$FRAMEWORKS_DIR/lib/libtk"* \
       "$FRAMEWORKS_DIR/lib/libtcl"* \
       "$FRAMEWORKS_DIR/lib/Tix"* \
       "$FRAMEWORKS_DIR/lib/itcl"* \
       "$FRAMEWORKS_DIR/lib/tdbc"* \
       "$FRAMEWORKS_DIR/lib/thread"* \
       "$FRAMEWORKS_DIR/lib/python${PYTHON_MAJ_MIN}/lib-dynload/_tkinter"* \
       "$FRAMEWORKS_DIR/share" 2>/dev/null || true

# --- Bundle module source code ---
echo "==> Bundling module source code..."
MODULES_DIR="$APP_PATH/Contents/Resources/modules"
rm -rf "$MODULES_DIR"
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
  # Use rsync to exclude unnecessary files
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

# --- Report bundle size ---
echo "==> Bundle contents:"
du -sh "$APP_PATH/Contents/Frameworks/python" | awk '{print "  Python: " $1}'
du -sh "$MODULES_DIR" | awk '{print "  Modules: " $1}'
du -sh "$APP_PATH" | awk '{print "  Total .app: " $1}'

# --- Code sign ---
echo "==> Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || {
  echo "  Warning: code signing failed (non-fatal for local testing)"
}

echo ""
echo "==> Build complete: $APP_PATH"

# --- Optionally create DMG ---
if [ "$CREATE_DMG" = true ]; then
  echo "==> Creating DMG..."
  bash "$SCRIPT_DIR/create-dmg.sh" "$APP_PATH" "1.0.0"
fi
