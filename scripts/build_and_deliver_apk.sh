#!/usr/bin/env bash
# build_and_deliver_apk.sh — Build the NMTK Flutter launcher APK and copy it to the
# Box-synced NMTK folder. macOS DMG delivery is opt-in.
#
# Usage:
#   scripts/build_and_deliver_apk.sh [OPTIONS]
#
# Options:
#   --debug        Build a debug build
#   --profile      Build a profile build (default)
#   --release      Build a release build
#   --with-dmg     Also build/copy the macOS DMG (off by default)
#   --apk-only     Only build/copy the Android APK (default; same as no flags)
#   --dmg-only     Only build/copy the macOS DMG (skip the Android APK)
#   --skip-build   Skip the flutter build steps; copy existing artifacts
#   --box-dir DIR  Copy artifacts to DIR after build (default: $NMTK_BOX_DIR or
#                  ~/Library/CloudStorage/Box-Box/NMTK/Builds)
#   --version VER  Version string used in the DMG filename (default: dev)
#   --sign ID      Codesign identity to pass through when building the DMG
#   -h, --help     Show this help message
#
# Examples:
#   scripts/build_and_deliver_apk.sh
#   scripts/build_and_deliver_apk.sh --debug
#   scripts/build_and_deliver_apk.sh --with-dmg
#   scripts/build_and_deliver_apk.sh --release --dmg-only
#   scripts/build_and_deliver_apk.sh --skip-build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_DIR="$REPO_ROOT/nmtk/neuro_toolkit"
APK_OUTPUT_DIR="$FLUTTER_DIR/build/app/outputs/flutter-apk"
MACOS_PRODUCTS_DIR="$FLUTTER_DIR/build/macos/Build/Products"
DMG_OUTPUT_DIR="$FLUTTER_DIR/build/deliver"

BUILD_MODE="profile"
BUILD_APK=true
BUILD_DMG=false
SKIP_BUILD=false
BOX_DIR="${NMTK_BOX_DIR:-}"
DMG_VERSION="dev"
SIGNING_IDENTITY=""

usage() {
  sed -n '2,24p' "$0" | sed 's/^# //' | sed 's/^#//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      BUILD_MODE="debug"
      shift
      ;;
    --profile)
      BUILD_MODE="profile"
      shift
      ;;
    --release)
      BUILD_MODE="release"
      shift
      ;;
    --with-dmg)
      BUILD_DMG=true
      shift
      ;;
    --apk-only)
      BUILD_DMG=false
      shift
      ;;
    --dmg-only)
      BUILD_APK=false
      BUILD_DMG=true
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --box-dir)
      BOX_DIR="${2:?--box-dir requires a value}"
      shift 2
      ;;
    --version)
      DMG_VERSION="${2:?--version requires a value}"
      shift 2
      ;;
    --sign)
      SIGNING_IDENTITY="${2:?--sign requires a value}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required but was not found on PATH." >&2
  exit 1
fi

apk_filename() {
  case "$BUILD_MODE" in
    debug) printf '%s\n' "app-debug.apk" ;;
    profile) printf '%s\n' "app-profile.apk" ;;
    *) printf '%s\n' "app-release.apk" ;;
  esac
}

xcode_config_name() {
  case "$BUILD_MODE" in
    debug) printf '%s\n' "Debug" ;;
    profile) printf '%s\n' "Profile" ;;
    *) printf '%s\n' "Release" ;;
  esac
}

dmg_filename() {
  printf 'NeuroMorphicToolKit-%s-macos.dmg\n' "$DMG_VERSION"
}

copy_to_box() {
  local file="$1"
  if [ -n "$BOX_DIR" ]; then
    bash "$SCRIPT_DIR/copy_build_to_box.sh" "$file" "$BOX_DIR"
  else
    bash "$SCRIPT_DIR/copy_build_to_box.sh" "$file"
  fi
}

deliver_apk() {
  if [ ! -f "$APK_PATH" ]; then
    echo "APK not found at $APK_PATH" >&2
    echo "Run without --skip-build, or build manually from nmtk/neuro_toolkit." >&2
    exit 1
  fi
  copy_to_box "$APK_PATH"
}

# Other agents/processes in this repo build the same Flutter project
# concurrently. Two `flutter build macos` runs racing on the same
# build/macos/Build/Products tree can corrupt the App.framework codesign
# (codesign fails with "replacing existing signature" / errSecInternalComponent).
# Serialize builds across invocations with a simple lock dir.
BUILD_LOCK_DIR="$FLUTTER_DIR/.build_and_deliver_apk.lock"

acquire_build_lock() {
  local waited=0
  local timeout=600
  while ! mkdir "$BUILD_LOCK_DIR" 2>/dev/null; do
    if [ "$waited" -ge "$timeout" ]; then
      echo "Timed out waiting for another build to finish (lock: $BUILD_LOCK_DIR)." >&2
      exit 1
    fi
    echo "Another build is in progress; waiting for the lock... (${waited}s)"
    sleep 5
    waited=$((waited + 5))
  done
  trap 'rmdir "$BUILD_LOCK_DIR" 2>/dev/null || true' EXIT
}

# codesign needs the login keychain unlocked to sign the macOS app. On a
# machine that's been idle (e.g. a headless dev box), the keychain can be
# locked, which makes the macOS build fail with a signing error. Unlock it
# up front; if it's already unlocked this is a harmless no-op.
unlock_login_keychain() {
  if [ "$(uname)" != "Darwin" ]; then
    return 0
  fi
  if ! command -v security >/dev/null 2>&1; then
    return 0
  fi
  echo "Unlocking login keychain for codesign..."
  if ! security unlock-keychain "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null; then
    echo "Warning: could not unlock login keychain; codesign may fail if it's locked." >&2
  fi
}

# flutter build macos occasionally fails with a codesign error
# ("replacing existing signature" / errSecInternalComponent) when it races
# another build touching the same App.framework. Retry a couple of times
# before giving up, since a clean re-run of the same command usually succeeds.
build_macos_with_retry() {
  local attempt=1
  local max_attempts=3
  while true; do
    if (
      cd "$FLUTTER_DIR"
      case "$BUILD_MODE" in
        debug) flutter build macos --debug ;;
        profile) flutter build macos --profile ;;
        *) flutter build macos --release ;;
      esac
    ); then
      return 0
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "flutter build macos failed after $max_attempts attempts." >&2
      return 1
    fi
    echo "flutter build macos failed (attempt $attempt/$max_attempts), likely a transient codesign conflict with a concurrent build. Retrying in 5s..." >&2
    attempt=$((attempt + 1))
    sleep 5
  done
}

APK_NAME="$(apk_filename)"
APK_PATH="$APK_OUTPUT_DIR/$APK_NAME"
DMG_NAME="$(dmg_filename)"
DMG_PATH="$DMG_OUTPUT_DIR/$DMG_NAME"

if [ "$BUILD_APK" = false ] && [ "$BUILD_DMG" = false ]; then
  echo "Nothing to do: no artifacts selected (e.g. --apk-only with --dmg-only)." >&2
  exit 1
fi

if [ "$SKIP_BUILD" = false ]; then
  acquire_build_lock

  if [ "$BUILD_APK" = true ]; then
    echo "Building $BUILD_MODE APK from $FLUTTER_DIR ..."
    (
      cd "$FLUTTER_DIR"
      case "$BUILD_MODE" in
        debug) flutter build apk --debug ;;
        # ponytail: --no-tree-shake-icons keeps the full zeta-icons font so a
        # stale subset cannot map codepoints to CJK fallback glyphs (CEL-178).
        profile) flutter build apk --profile --no-tree-shake-icons ;;
        *) flutter build apk --release --no-tree-shake-icons ;;
      esac
    )
    deliver_apk
  fi

  if [ "$BUILD_DMG" = true ]; then
    unlock_login_keychain
    echo "Building $BUILD_MODE macOS app from $FLUTTER_DIR ..."
    dmg_build_ok=false
    if build_macos_with_retry; then
      APP_PATH="$MACOS_PRODUCTS_DIR/$(xcode_config_name)/neuro_toolkit.app"
      mkdir -p "$DMG_OUTPUT_DIR"
      echo "Building DMG from $APP_PATH ..."
      if (
        cd "$DMG_OUTPUT_DIR"
        bash "$REPO_ROOT/nmtk/installer/macos/create-dmg.sh" "$APP_PATH" "$DMG_VERSION" "$SIGNING_IDENTITY"
      ); then
        dmg_build_ok=true
      fi
    fi
    if [ "$dmg_build_ok" = false ]; then
      echo "Warning: DMG build failed." >&2
      if [ "$BUILD_APK" = false ]; then
        exit 1
      fi
      echo "Continuing with APK only." >&2
    fi
  fi
fi

if [ "$BUILD_APK" = true ] && [ "$SKIP_BUILD" = true ]; then
  deliver_apk
fi

if [ "$BUILD_DMG" = true ]; then
  if [ ! -f "$DMG_PATH" ]; then
    if [ "$BUILD_APK" = true ]; then
      echo "Warning: DMG not available; delivered APK only." >&2
    else
      echo "DMG not found at $DMG_PATH" >&2
      echo "Run without --skip-build, or build manually with nmtk/installer/macos/create-dmg.sh." >&2
      exit 1
    fi
  else
    copy_to_box "$DMG_PATH"
  fi
fi

echo "Done."
