#!/usr/bin/env bash
# copy_build_to_box.sh — Copy a build artifact into the Box-synced NMTK folder.
#
# Usage: copy_build_to_box.sh SOURCE_FILE [BOX_DIR] [DEST_NAME]
#
# BOX_DIR defaults to $NMTK_BOX_DIR or ~/Library/CloudStorage/Box-Box/NMTK/Builds.
# DEST_NAME renames the artifact at the destination (e.g. nmtk-profile.apk);
# it defaults to the source basename.
# If the Box sync folder is missing, prints a warning and exits 0 (non-fatal).

set -euo pipefail

SOURCE="${1:?source file required}"
BOX_DIR="${2:-${NMTK_BOX_DIR:-$HOME/Library/CloudStorage/Box-Box/NMTK/Builds}}"
DEST_NAME="${3:-}"

if [ ! -f "$SOURCE" ]; then
  echo "Box copy skipped: source not found: $SOURCE" >&2
  exit 0
fi

# ponytail: only mkdir under an existing Box NMTK root; upgrade path is probe Box.app sync state.
BOX_NMTK_ROOT="$(dirname "$BOX_DIR")"
if [ ! -d "$BOX_NMTK_ROOT" ]; then
  echo "Warning: Box folder not found at $BOX_NMTK_ROOT — artifact not copied (Box may not be installed or synced)." >&2
  exit 0
fi

mkdir -p "$BOX_DIR"
DEST="$BOX_DIR/${DEST_NAME:-$(basename "$SOURCE")}"
BASENAME="$(basename "$DEST")"

copy_to_dest() {
  local target="$1"
  rm -f "$target" 2>/dev/null || true
  cp -X -f "$SOURCE" "$target" 2>/dev/null
}

# 1. Try direct copy to standard destination
if copy_to_dest "$DEST"; then
  echo "Box copy: $DEST"
  exit 0
fi

# 2. Brief retry in case Box sync is temporarily holding the file
sleep 1
if copy_to_dest "$DEST"; then
  echo "Box copy: $DEST"
  exit 0
fi

# 3. Fallback for remote/SSH sessions where Box/macOS locks an existing file
EXT="${BASENAME##*.}"
STEM="${BASENAME%.*}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FALLBACK_DEST="$BOX_DIR/${STEM}-${TIMESTAMP}.${EXT}"

if copy_to_dest "$FALLBACK_DEST"; then
  echo "Box copy: $FALLBACK_DEST (saved with timestamp because primary destination is locked by Box/macOS)"
  exit 0
fi

echo "Warning: could not copy to Box at $DEST (permissions or sync may block remote/SSH copies)." >&2
echo "Artifact remains at: $SOURCE" >&2
exit 0
