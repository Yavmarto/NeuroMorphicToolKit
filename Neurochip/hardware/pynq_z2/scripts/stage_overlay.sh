#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/build/out}"
STAGING_DIR="${STAGING_DIR:-$ROOT_DIR/../../overlay_staging/pynq_z2}"

BITSTREAM="$OUT_DIR/snn_overlay.bit"
HWH="$OUT_DIR/snn_overlay.hwh"
MANIFEST="$OUT_DIR/overlay_manifest.json"

for path in "$BITSTREAM" "$HWH" "$MANIFEST"; do
  if [[ ! -f "$path" ]]; then
    echo "Required build artifact is missing: $path" >&2
    exit 1
  fi
done

mkdir -p "$STAGING_DIR"
cp -f "$BITSTREAM" "$STAGING_DIR/snn_overlay.bit"
cp -f "$HWH" "$STAGING_DIR/snn_overlay.hwh"
cp -f "$MANIFEST" "$STAGING_DIR/overlay_manifest.json"

echo "[pynq_z2] staged overlay package into $STAGING_DIR"
