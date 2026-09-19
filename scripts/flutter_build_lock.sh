#!/usr/bin/env bash
# flutter_build_lock.sh — Serialize Flutter build/run commands against one project.
#
# Every `flutter build macos` / `flutter run -d macos` for nmtk/neuro_toolkit
# shares build/macos, macos/Flutter/ephemeral, and macos/Pods. Two builds
# writing that tree at the same time corrupt in-progress artifacts. Observed
# failures:
#   - "Binary .../FlutterMacOS.framework/Versions/A/FlutterMacOS does not
#     contain architectures" (the lipo check read a framework mid-write)
#   - App.framework codesign conflicts ("replacing existing signature")
#
# scripts/build_and_deliver_apk.sh takes this same lock for its whole build
# phase. Ad-hoc interactive runs should take it too:
#
#   scripts/flutter_build_lock.sh run -d macos
#   scripts/flutter_build_lock.sh build macos --profile
#
# Scripts that hold the lock across several commands can source this file:
#
#   . scripts/flutter_build_lock.sh
#   acquire_flutter_build_lock
#   ...run multiple flutter commands...
#   release_flutter_build_lock
#
# Environment:
#   NMTK_FLUTTER_DIR          Flutter project root (default:
#                             <repo>/nmtk/neuro_toolkit)
#   NMTK_FLUTTER_LOCK_DIR     Lock directory (default:
#                             <project>/.flutter_build.lock)
#   NMTK_FLUTTER_LOCK_TIMEOUT Seconds to wait for the lock (default: 1800)
#   NMTK_FLUTTER_LOCK_POLL    Seconds between checks (default: 5)
#   NMTK_FLUTTER_LOCK_STALE_AFTER
#                             Seconds before a holder-less lock is reclaimed
#                             (default: 60)

set -euo pipefail

_flutter_lock_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/.." && pwd
}

FLUTTER_PROJECT_DIR="${NMTK_FLUTTER_DIR:-$(_flutter_lock_repo_root)/nmtk/neuro_toolkit}"
FLUTTER_BUILD_LOCK_DIR="${NMTK_FLUTTER_LOCK_DIR:-$FLUTTER_PROJECT_DIR/.flutter_build.lock}"
FLUTTER_BUILD_LOCK_TIMEOUT="${NMTK_FLUTTER_LOCK_TIMEOUT:-1800}"
FLUTTER_BUILD_LOCK_POLL="${NMTK_FLUTTER_LOCK_POLL:-5}"
FLUTTER_BUILD_LOCK_STALE_AFTER="${NMTK_FLUTTER_LOCK_STALE_AFTER:-60}"

# True when the PID recorded by the current lock holder is still running.
_flutter_lock_holder_alive() {
  local pid_file="$FLUTTER_BUILD_LOCK_DIR/holder.pid"
  [ -f "$pid_file" ] || return 1
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

# Age of the lock directory in seconds, or '' when it cannot be read.
_flutter_lock_age_seconds() {
  local mtime now
  case "$(uname)" in
    Darwin) mtime="$(stat -f %m "$FLUTTER_BUILD_LOCK_DIR" 2>/dev/null || echo '')" ;;
    *) mtime="$(stat -c %Y "$FLUTTER_BUILD_LOCK_DIR" 2>/dev/null || echo '')" ;;
  esac
  [ -n "$mtime" ] || return 1
  now="$(date +%s)"
  echo $((now - mtime))
}

acquire_flutter_build_lock() {
  local waited=0
  while ! mkdir "$FLUTTER_BUILD_LOCK_DIR" 2>/dev/null; do
    # A holder that died without releasing leaves the lock dir behind. Reclaim
    # it, but only after the stale grace period so we never steal a lock that
    # a holder is in the middle of creating (mkdir then pid write).
    local age
    age="$(_flutter_lock_age_seconds || echo '')"
    if ! _flutter_lock_holder_alive && [ -n "$age" ] && [ "$age" -ge "$FLUTTER_BUILD_LOCK_STALE_AFTER" ]; then
      echo "Reclaiming stale Flutter build lock at $FLUTTER_BUILD_LOCK_DIR (holder is gone)." >&2
      rm -rf "$FLUTTER_BUILD_LOCK_DIR"
      continue
    fi
    if [ "$waited" -ge "$FLUTTER_BUILD_LOCK_TIMEOUT" ]; then
      local holder
      holder="$(cat "$FLUTTER_BUILD_LOCK_DIR/holder.pid" 2>/dev/null || echo unknown)"
      echo "Timed out after ${FLUTTER_BUILD_LOCK_TIMEOUT}s waiting for the Flutter build lock." >&2
      echo "Lock: $FLUTTER_BUILD_LOCK_DIR (holder PID: $holder)." >&2
      exit 1
    fi
    echo "Another Flutter build/run holds the lock; waiting... (${waited}s)"
    sleep "$FLUTTER_BUILD_LOCK_POLL"
    waited=$((waited + FLUTTER_BUILD_LOCK_POLL))
  done
  echo "$$" > "$FLUTTER_BUILD_LOCK_DIR/holder.pid"
  trap 'release_flutter_build_lock' EXIT
}

release_flutter_build_lock() {
  trap - EXIT
  rm -rf "$FLUTTER_BUILD_LOCK_DIR"
}

# When executed directly, run `flutter "$@"` under the lock.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter is required but was not found on PATH." >&2
    exit 1
  fi
  if [ "$#" -eq 0 ]; then
    echo "Usage: scripts/flutter_build_lock.sh <flutter args...>" >&2
    echo "Example: scripts/flutter_build_lock.sh run -d macos" >&2
    exit 1
  fi
  acquire_flutter_build_lock
  flutter "$@"
fi
