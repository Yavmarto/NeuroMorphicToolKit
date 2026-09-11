#!/usr/bin/env bash
# copy_build_to_box.sh — Copy a build artifact into the Box-synced NMTK folder.
#
# Usage: copy_build_to_box.sh SOURCE_FILE [BOX_DIR]
#
# BOX_DIR defaults to $NMTK_BOX_DIR or ~/Library/CloudStorage/Box-Box/NMTK/Builds.
# If the Box sync folder is missing, prints a warning and exits 0 (non-fatal).

set -euo pipefail

SOURCE="${1:?source file required}"
BOX_DIR="${2:-${NMTK_BOX_DIR:-$HOME/Library/CloudStorage/Box-Box/NMTK/Builds}}"

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
DEST="$BOX_DIR/$(basename "$SOURCE")"
cp -f "$SOURCE" "$DEST"
echo "Box copy: $DEST"
