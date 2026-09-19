#!/usr/bin/env bash
# build_and_deliver_apk.sh — Build the NMTK Flutter launcher (macOS DMG, then Android APK)
# and copy artifacts to the Box-synced NMTK folder.
# The APK is renamed to nmtk-<buildtype>.apk when copied (e.g. nmtk-profile.apk).
#
# Usage:
#   scripts/build_and_deliver_apk.sh [OPTIONS]
#
# Options:
#   --debug        Build a debug build
#   --profile      Build a profile build (default)
#   --release      Build a release build
#   --apk-only     Only build/copy the Android APK (skip the macOS DMG)
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
#   scripts/build_and_deliver_apk.sh --release --apk-only
#   scripts/build_and_deliver_apk.sh --dmg-only
#   scripts/build_and_deliver_apk.sh --skip-build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Shared serialization with ad-hoc `flutter run -d macos` / `flutter build
# macos` sessions and other packaging runs touching the same project tree.
# Sourcing this defines FLUTTER_PROJECT_DIR and acquire_flutter_build_lock();
# see scripts/flutter_build_lock.sh for the documented interactive wrapper.
# shellcheck source=scripts/flutter_build_lock.sh
. "$SCRIPT_DIR/flutter_build_lock.sh"

FLUTTER_DIR="$FLUTTER_PROJECT_DIR"
APK_OUTPUT_DIR="$FLUTTER_DIR/build/app/outputs/flutter-apk"
MACOS_PRODUCTS_DIR="$FLUTTER_DIR/build/macos/Build/Products"
DMG_OUTPUT_DIR="$FLUTTER_DIR/build/deliver"

BUILD_MODE="profile"
BUILD_APK=true
BUILD_DMG=true
SKIP_BUILD=false
BOX_DIR="${NMTK_BOX_DIR:-}"
DMG_VERSION="dev"
SIGNING_IDENTITY=""

usage() {
  sed -n '2,25p' "$0" | sed 's/^# //' | sed 's/^#//'
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

apk_dest_name() {
  printf 'nmtk-%s.apk\n' "$BUILD_MODE"
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
  local dest_name="${2:-}"
  if [ -n "$BOX_DIR" ]; then
    bash "$SCRIPT_DIR/copy_build_to_box.sh" "$file" "$BOX_DIR" "$dest_name"
  else
    bash "$SCRIPT_DIR/copy_build_to_box.sh" "$file" "" "$dest_name"
  fi
}

# Non-release builds auto-connect to the dev backend without credentials
# (CEL-220). Override the host with NMTK_DEV_SERVER_HOST when packaging.
# ponytail: one define today; avoid mapfile (missing on macOS bash 3.2).
flutter_non_release_define() {
  case "$BUILD_MODE" in
    release) printf '' ;;
    *)
      printf '%s' "--dart-define=NMTK_DEV_SERVER_HOST=${NMTK_DEV_SERVER_HOST:-192.168.2.90}"
      ;;
  esac
}

deliver_apk() {
  if [ ! -f "$APK_PATH" ]; then
    echo "APK not found at $APK_PATH" >&2
    echo "Run without --skip-build, or build manually from nmtk/neuro_toolkit." >&2
    exit 1
  fi
  copy_to_box "$APK_PATH" "$(apk_dest_name)"
}

deliver_dmg() {
  if [ ! -f "$DMG_PATH" ]; then
    if [ "$BUILD_APK" = true ]; then
      echo "Warning: DMG not available; continuing with APK only." >&2
      return 1
    fi
    echo "DMG not found at $DMG_PATH" >&2
    echo "Run without --skip-build, or build manually with nmtk/installer/macos/create-dmg.sh." >&2
    exit 1
  fi
  copy_to_box "$DMG_PATH"
}

# Build serialization lives in scripts/flutter_build_lock.sh (sourced above).
# It takes the same lock any interactive `flutter run -d macos` session should
# take, so packaging runs and dev runs cannot write build/macos at once.

# codesign needs the login keychain unlocked to sign the macOS app. Only try
# interactively — SSH/agent runs cannot answer the password prompt.
unlock_login_keychain() {
  if [ "$(uname)" != "Darwin" ]; then
    return 0
  fi
  if ! command -v security >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -t 0 ]; then
    return 0
  fi
  echo "Unlocking login keychain for codesign..."
  if ! security unlock-keychain "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null; then
    echo "Warning: could not unlock login keychain; codesign may fail if it's locked." >&2
  fi
}

# flutter build macos can fail when another Flutter process is writing the
# shared build/macos tree at the same time:
#   - codesign conflict on App.framework ("replacing existing signature" /
#     errSecInternalComponent).
# The lock above serializes packaging runs, but an ad-hoc `flutter run -d
# macos` can still race us. Retry the WHOLE `flutter build macos` command (not
# just codesign): a clean re-run after the racing build stops writing succeeds.
#
# The SAME error text also appears for a non-race reason on Xcode 27: Flutter
# 3.44.2's thinFramework runs `lipo <fat> -verify_arch <arch> <arch>`, and the
# Xcode 27 lipo rejects more than one arch there ("-verify_arch requires
# exactly one input file"), so every universal build fails at
# profile_unpack_macos. See flutter/flutter#188461 (fixed upstream by #189792).
# On that toolchain a retry can never succeed, so fall back once to a
# single-arch build. Set NMTK_MACOS_NO_SINGLE_ARCH_FALLBACK=1 to fail instead.
build_macos_host_arch() {
  case "$(uname -m)" in
    arm64) printf 'arm64' ;;
    x86_64) printf 'x86_64' ;;
    *) printf '' ;;
  esac
}

flutter_build_macos() {
  local archs_override="${1:-}"
  (
    cd "$FLUTTER_DIR"
    if [ -n "$archs_override" ]; then
      export FLUTTER_XCODE_ARCHS="$archs_override"
    fi
    _define="$(flutter_non_release_define)"
    case "$BUILD_MODE" in
      # ponytail: --no-tree-shake-icons keeps the full zeta-icons font so a
      # stale subset cannot map codepoints to missing/CJK fallback glyphs
      # (CEL-178, CEL-229).
      debug) flutter build macos --debug --no-tree-shake-icons ${_define:+"$_define"} ;;
      profile) flutter build macos --profile --no-tree-shake-icons ${_define:+"$_define"} ;;
      *) flutter build macos --release --no-tree-shake-icons ;;
    esac
  )
}

build_macos_with_retry() {
  local attempt=1
  local max_attempts="${NMTK_MACOS_BUILD_ATTEMPTS:-5}"
  local retry_sleep="${NMTK_MACOS_BUILD_RETRY_SLEEP:-5}"
  local arch_retry_sleep="${NMTK_MACOS_ARCH_RETRY_SLEEP:-15}"
  local arch_retry_sleep_max="${NMTK_MACOS_ARCH_RETRY_SLEEP_MAX:-120}"
  local archs_override=""
  local allow_single_arch=true
  local host_arch
  host_arch="$(build_macos_host_arch)"
  if [ "${NMTK_MACOS_NO_SINGLE_ARCH_FALLBACK:-0}" = "1" ]; then
    allow_single_arch=false
  fi
  local log
  log="$(mktemp "${TMPDIR:-/tmp}/nmtk-macos-build.XXXXXX")"
  while true; do
    local rc=0
    if flutter_build_macos "$archs_override" 2>&1 | tee "$log"; then
      rm -f "$log"
      return 0
    else
      rc="${PIPESTATUS[0]}"
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "flutter build macos failed after $max_attempts attempts (last exit: $rc)." >&2
      echo "Last build output:" >&2
      tail -n 40 "$log" >&2 || true
      rm -f "$log"
      return 1
    fi
    if grep -q "does not contain architectures" "$log"; then
      if [ -z "$archs_override" ] && [ "$allow_single_arch" = true ] && [ -n "$host_arch" ]; then
        archs_override="$host_arch"
        echo "WARNING: the local Xcode lipo rejected the universal-arch check (Xcode 27 lipo bug, flutter/flutter#188461)." >&2
        echo "WARNING: falling back to a single-arch (${host_arch}) macOS build; the resulting app/DMG will NOT run on Intel Macs." >&2
        echo "WARNING: upgrade Flutter (fixed in 3.45+) or downgrade Xcode to build universal again. Set NMTK_MACOS_NO_SINGLE_ARCH_FALLBACK=1 to fail instead." >&2
      else
        echo "flutter build macos reported a framework arch check (attempt $attempt/$max_attempts); retrying in ${arch_retry_sleep}s..." >&2
        sleep "$arch_retry_sleep"
        arch_retry_sleep=$((arch_retry_sleep * 2))
        if [ "$arch_retry_sleep" -gt "$arch_retry_sleep_max" ]; then
          arch_retry_sleep="$arch_retry_sleep_max"
        fi
      fi
    else
      echo "flutter build macos failed (attempt $attempt/$max_attempts), likely a transient conflict with a concurrent build; retrying in ${retry_sleep}s..." >&2
      sleep "$retry_sleep"
    fi
    attempt=$((attempt + 1))
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
  acquire_flutter_build_lock

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
        NMTK_SKIP_BOX_COPY=1 bash "$REPO_ROOT/nmtk/installer/macos/create-dmg.sh" "$APP_PATH" "$DMG_VERSION" "$SIGNING_IDENTITY"
      ); then
        dmg_build_ok=true
        deliver_dmg || true
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

  if [ "$BUILD_APK" = true ]; then
    echo "Building $BUILD_MODE APK from $FLUTTER_DIR ..."
    (
      cd "$FLUTTER_DIR"
      _define="$(flutter_non_release_define)"
      case "$BUILD_MODE" in
        debug) flutter build apk --debug ${_define:+"$_define"} ;;
        # ponytail: --no-tree-shake-icons keeps the full zeta-icons font so a
        # stale subset cannot map codepoints to CJK fallback glyphs (CEL-178).
        profile) flutter build apk --profile --no-tree-shake-icons ${_define:+"$_define"} ;;
        *) flutter build apk --release --no-tree-shake-icons ;;
      esac
    )
    deliver_apk
  fi
fi

if [ "$BUILD_DMG" = true ] && [ "$SKIP_BUILD" = true ]; then
  deliver_dmg || [ "$BUILD_APK" = true ]
fi

if [ "$BUILD_APK" = true ] && [ "$SKIP_BUILD" = true ]; then
  deliver_apk
fi

echo "Done."
