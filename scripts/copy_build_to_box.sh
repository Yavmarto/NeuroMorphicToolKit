#!/usr/bin/env bash
# copy_build_to_box.sh — Copy a build artifact into the Box-synced NMTK folder.
#
# Usage: copy_build_to_box.sh SOURCE_FILE [BOX_DIR] [DEST_NAME]
#
# BOX_DIR defaults to $NMTK_BOX_DIR or ~/Library/CloudStorage/Box-Box/2. NMTK/Builds.
# DEST_NAME renames the artifact at the destination (e.g. nmtk-profile.apk);
# it defaults to the source basename.
# If the Box sync folder is missing, prints a warning and exits 0 (non-fatal).
#
# Important: never `rm` files under Box Drive / File Provider paths. Unlink can
# hang indefinitely while Box holds the cloud file; that made build_and_deliver
# look stuck after a successful APK build.

set -euo pipefail

SOURCE="${1:?source file required}"
BOX_DIR="${2:-${NMTK_BOX_DIR:-$HOME/Library/CloudStorage/Box-Box/2. NMTK/Builds}}"
DEST_NAME="${3:-}"
FS_TIMEOUT_SEC="${BOX_COPY_TIMEOUT_SEC:-45}"

if [ ! -f "$SOURCE" ]; then
  echo "Box copy skipped: source not found: $SOURCE" >&2
  exit 0
fi

BOX_NMTK_ROOT="$(dirname "$BOX_DIR")"
if [ ! -d "$BOX_NMTK_ROOT" ]; then
  echo "Warning: Box folder not found at $BOX_NMTK_ROOT — artifact not copied (Box may not be installed or synced)." >&2
  exit 0
fi

with_timeout() {
  local secs="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
}

if ! with_timeout "$FS_TIMEOUT_SEC" mkdir -p "$BOX_DIR" 2>/dev/null; then
  echo "Warning: timed out creating Box dir $BOX_DIR — artifact not copied." >&2
  echo "Artifact remains at: $SOURCE" >&2
  exit 0
fi

DEST="$BOX_DIR/${DEST_NAME:-$(basename "$SOURCE")}"
BASENAME="$(basename "$DEST")"

copy_to_dest() {
  local target="$1"
  with_timeout "$FS_TIMEOUT_SEC" cp -X -f "$SOURCE" "$target" 2>/dev/null
}

if copy_to_dest "$DEST"; then
  echo "Box copy: $DEST"
  exit 0
fi

sleep 1
if copy_to_dest "$DEST"; then
  echo "Box copy: $DEST"
  exit 0
fi

EXT="${BASENAME##*.}"
STEM="${BASENAME%.*}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FALLBACK_DEST="$BOX_DIR/${STEM}-${TIMESTAMP}.${EXT}"

if copy_to_dest "$FALLBACK_DEST"; then
  echo "Box copy: $FALLBACK_DEST (saved with timestamp because primary destination is locked by Box/macOS)"
  exit 0
fi

echo "Warning: could not copy to Box at $DEST within ${FS_TIMEOUT_SEC}s (Box sync may be stuck)." >&2
echo "Artifact remains at: $SOURCE" >&2
exit 0
