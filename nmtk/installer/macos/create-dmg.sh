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

# ponytail: hdiutil grep + 3 retries; upgrade path is create-dmg --skip-jenkins if flakiness persists.
detach_stale_rw_dmgs() {
  local dmg_dir="$1"
  while read -r dev; do
    [ -z "$dev" ] && continue
    echo "==> Detaching stale DMG volume: $dev"
    hdiutil detach "$dev" -force 2>/dev/null || hdiutil detach "$dev" 2>/dev/null || true
  done < <(
    hdiutil info 2>/dev/null | awk '
      /^image-path/ {
        path = substr($0, index($0, ":") + 2)
        if (path ~ /\/rw\.[0-9]+\.NeuroMorphicToolKit-/) pending = 1
        else pending = 0
      }
      /^\/dev\/disk[0-9]+[[:space:]]/ && pending {
        print $1
        pending = 0
      }
    '
  )
  rm -f "$dmg_dir"/rw.*.NeuroMorphicToolKit-*.dmg 2>/dev/null || true
}

OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
MAX_CREATE_DMG_ATTEMPTS=3
# create-dmg's Finder AppleScript needs a foreground Finder session; agent/SSH
# runs often have none. Waking Finder once is enough for the retry window.
if [ "$(uname)" = "Darwin" ]; then
  open -a Finder 2>/dev/null || true
fi
attempt=1
while true; do
  detach_stale_rw_dmgs "$OUTPUT_DIR"
  rm -f "$OUTPUT_PATH"

  echo "==> Building DMG: $OUTPUT_FILE (attempt $attempt/$MAX_CREATE_DMG_ATTEMPTS)"
  # First attempt tries the Finder-styled layout; once that AppleScript step
  # has timed out (-1712), retries can't succeed without a foreground Finder
  # session (e.g. headless/agent runs), so skip straight to a plain DMG.
  EXTRA_FLAGS=""
  if [ "$attempt" -gt 1 ]; then
    EXTRA_FLAGS="--skip-jenkins"
  fi
  if create-dmg \
    $EXTRA_FLAGS \
    --volname "NeuroMorphic ToolKit ${VERSION}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 400 150 \
    --no-internet-enable \
    "$OUTPUT_PATH" \
    "$STAGING_DIR/"; then
    break
  fi

  detach_stale_rw_dmgs "$OUTPUT_DIR"
  if [ "$attempt" -ge "$MAX_CREATE_DMG_ATTEMPTS" ]; then
    echo "Error: create-dmg failed after $MAX_CREATE_DMG_ATTEMPTS attempts." >&2
    exit 1
  fi
  echo "create-dmg failed (attempt $attempt/$MAX_CREATE_DMG_ATTEMPTS); retrying in 3s..." >&2
  attempt=$((attempt + 1))
  sleep 3
done

# Cleanup staging directory
rm -rf "$STAGING_DIR"

# Sign DMG if identity provided
if [ -n "$SIGNING_IDENTITY" ]; then
  export MACOS_SIGNING_IDENTITY="$SIGNING_IDENTITY"
  bash "$SCRIPT_DIR/sign-and-notarize.sh" sign-dmg "$OUTPUT_PATH"
fi

echo "Created $OUTPUT_FILE ($(du -sh "$OUTPUT_PATH" | awk '{print $1}'))"

bash "$REPO_ROOT/scripts/copy_build_to_box.sh" "$OUTPUT_PATH"
