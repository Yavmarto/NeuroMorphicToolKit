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
# Usage: ./build-standalone.sh [--skip-flutter] [--dmg] [--version 1.2.3]
#
# --version names the DMG. When omitted it is read from
# nmtk/neuro_toolkit/pubspec.yaml, which the release pipeline bumps; the DMG
# used to be hardcoded to "dev" so every published release carried the same
# unversioned filename.
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
SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-}"
NOTARIZE=false
VERSION=""
SIGN_HELPER="$SCRIPT_DIR/sign-and-notarize.sh"

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-flutter) SKIP_FLUTTER=true; shift ;;
    --dmg) CREATE_DMG=true; shift ;;
    --sign) SIGNING_IDENTITY="$2"; shift 2 ;;
    --notarize) NOTARIZE=true; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [ -z "$VERSION" ]; then
  VERSION="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
    "$TOOLKIT_DIR/pubspec.yaml" | head -1)"
fi
VERSION="${VERSION:-0.0.0-dev}"

if [ "$NOTARIZE" = false ]; then
  case "${MACOS_NOTARIZE:-}" in
    1|true|TRUE|yes|YES) NOTARIZE=true ;;
  esac
fi

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
if [ -d "$PREV_APP/Contents/Resources/scripts" ]; then
  echo "==> Cleaning previous bundled launcher scripts from build output..."
  rm -rf "$PREV_APP/Contents/Resources/scripts"
fi
if [ -d "$PREV_APP/Contents/Resources/nmtk" ]; then
  echo "==> Cleaning previous bundled launcher package from build output..."
  rm -rf "$PREV_APP/Contents/Resources/nmtk"
fi
if [ -d "$PREV_APP/Contents/Resources/bin" ] \
   || [ -d "$PREV_APP/Contents/Resources/monitoring" ] \
   || [ -f "$PREV_APP/Contents/Resources/docker-compose.yml" ]; then
  echo "==> Cleaning previous bundled deploy manifests / tools from build output..."
  rm -rf "$PREV_APP/Contents/Resources/bin" \
         "$PREV_APP/Contents/Resources/monitoring" \
         "$PREV_APP/Contents/Resources/docker-compose.yml" \
         "$PREV_APP/Contents/Resources/docker-compose.prod.yml"
fi

# --- Build Flutter app ---
if [ "$SKIP_FLUTTER" = false ]; then
  echo "==> Building Flutter macOS app..."
  cd "$TOOLKIT_DIR"
  flutter pub get
  # ponytail: --no-tree-shake-icons keeps the full zeta-icons font (CEL-178, CEL-229).
  flutter build macos --release --no-tree-shake-icons
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
# include/python3.12 looks like a nested bundle to codesign (CEL-348).
rm -rf "$FRAMEWORKS_DIR/include" \
       "$FRAMEWORKS_DIR/lib/python${PYTHON_MAJ_MIN}/test" \
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

MODULES=(neurocnl Neurochip Neurobench Neurosense Neurohub Neuro-Dream-Hand)

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
    --exclude='frontend/.dart_tool' \
    "$SRC/" "$DEST/"
done

# --- Bundle launcher control entrypoints ---
echo "==> Bundling launcher control service..."
mkdir -p "$APP_PATH/Contents/Resources/scripts"
cp "$REPO_ROOT/scripts/launcher_control_service.py" \
  "$APP_PATH/Contents/Resources/scripts/launcher_control_service.py"

mkdir -p "$APP_PATH/Contents/Resources/nmtk"
rsync -a \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  "$REPO_ROOT/nmtk/launcher_control/" \
  "$APP_PATH/Contents/Resources/nmtk/launcher_control/"

# --- Bundle deployment manifests (source-free server setup) ---
# The launcher resolves these under REPO_ROOT, which is Contents/Resources
# in a bundle (nmtk/launcher_control/config.py). Shipping them lets the app
# stand up a remote backend by pulling published images — no repo needed.
echo "==> Bundling deployment manifests..."
RES_DIR="$APP_PATH/Contents/Resources"
cp "$REPO_ROOT/docker-compose.yml"      "$RES_DIR/docker-compose.yml"
cp "$REPO_ROOT/docker-compose.prod.yml" "$RES_DIR/docker-compose.prod.yml"
rm -rf "$RES_DIR/monitoring"
rsync -a --exclude='__pycache__' "$REPO_ROOT/monitoring/" "$RES_DIR/monitoring/"

# --- Bundle sshpass (SSH password auth with no host dependency) ---
# A clean end-user Mac has no sshpass. The launcher prefers
# Contents/Resources/bin/sshpass (deployment_executors._bundled_or_path).
# Provide SSHPASS_BIN=/path/to/sshpass to use a specific (e.g. universal)
# binary; otherwise copy from PATH; otherwise build from source.
echo "==> Bundling sshpass..."
BIN_DIR="$RES_DIR/bin"
mkdir -p "$BIN_DIR"
if [ -n "${SSHPASS_BIN:-}" ] && [ -x "$SSHPASS_BIN" ]; then
  cp "$SSHPASS_BIN" "$BIN_DIR/sshpass"
elif command -v sshpass >/dev/null 2>&1; then
  cp "$(command -v sshpass)" "$BIN_DIR/sshpass"
else
  echo "  sshpass not on PATH; building from source..."
  SSHPASS_VER=1.10
  TMP_SP="$(mktemp -d)"
  if curl -fsSL "https://downloads.sourceforge.net/project/sshpass/sshpass/${SSHPASS_VER}/sshpass-${SSHPASS_VER}.tar.gz" -o "$TMP_SP/sshpass.tar.gz" \
     && tar -xzf "$TMP_SP/sshpass.tar.gz" -C "$TMP_SP" \
     && ( cd "$TMP_SP/sshpass-${SSHPASS_VER}" \
          && ./configure --prefix="$TMP_SP/out" >/dev/null \
          && make >/dev/null && make install >/dev/null ); then
    cp "$TMP_SP/out/bin/sshpass" "$BIN_DIR/sshpass"
  else
    echo "  WARNING: could not obtain sshpass — SSH password auth will not"
    echo "           work in the bundled app. Set SSHPASS_BIN or install sshpass."
  fi
  rm -rf "$TMP_SP"
fi
if [ -f "$BIN_DIR/sshpass" ]; then
  chmod +x "$BIN_DIR/sshpass"
  # Signed by the code-sign step below (ad-hoc --deep, or the sign helper).
fi

# --- Report bundle size ---
echo "==> Bundle contents:"
du -sh "$APP_PATH/Contents/Frameworks/python" | awk '{print "  Python: " $1}'
du -sh "$MODULES_DIR" | awk '{print "  Modules: " $1}'
du -sh "$APP_PATH" | awk '{print "  Total .app: " $1}'

# --- Code sign ---
if [ -n "$SIGNING_IDENTITY" ]; then
  export MACOS_SIGNING_IDENTITY="$SIGNING_IDENTITY"
  bash "$SIGN_HELPER" sign-app "$APP_PATH"
else
  bash "$SIGN_HELPER" sign-app-adhoc "$APP_PATH" || {
    echo "  Warning: code signing failed (non-fatal for local testing)"
  }
fi

echo ""
echo "==> Build complete: $APP_PATH"

# --- Notarize .app (if no DMG) ---
# Usually it's better to notarize the DMG, but if user just wants the .app:
if [ "$NOTARIZE" = true ] && [ "$CREATE_DMG" = false ]; then
  export MACOS_NOTARIZE=true
  bash "$SIGN_HELPER" notarize "$APP_PATH"
fi

# --- Optionally create DMG ---
if [ "$CREATE_DMG" = true ]; then
  echo "==> Creating DMG..."
  bash "$SCRIPT_DIR/create-dmg.sh" "$APP_PATH" "$VERSION" "$SIGNING_IDENTITY"

  DMG_FILE="NeuroMorphicToolKit-${VERSION}-macos.dmg"
  if [ "$NOTARIZE" = true ]; then
    export MACOS_NOTARIZE=true
    bash "$SIGN_HELPER" notarize "$DMG_FILE"
  fi
fi
