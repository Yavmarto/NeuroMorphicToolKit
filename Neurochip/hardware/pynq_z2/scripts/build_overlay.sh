#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/build/out}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This build flow requires a Linux x86_64 host with Vivado/Vitis HLS installed." >&2
  exit 1
fi

if ! command -v vitis_hls >/dev/null 2>&1; then
  echo "vitis_hls was not found in PATH." >&2
  exit 1
fi

if ! command -v vivado >/dev/null 2>&1; then
  echo "vivado was not found in PATH." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "[pynq_z2] synthesizing HLS IP"
vitis_hls -f "$ROOT_DIR/hls/build_hls.tcl"

echo "[pynq_z2] building Vivado design"
vivado -mode batch -source "$ROOT_DIR/vivado/build_overlay.tcl" -tclargs "$OUT_DIR"

# Take the register offsets from the hardware that was just built, never from
# whatever was last typed into the manifest by hand.  Overlay-v1's manifest
# disagreed with its own bitstream on every scalar argument, and nothing in the
# build compared them.
echo "[pynq_z2] resolving register offsets from the hardware handoff"
python3 "$ROOT_DIR/scripts/sync_manifest_offsets.py" --write \
  --manifest "$ROOT_DIR/overlay_manifest.json" \
  --hwh "$OUT_DIR/snn_overlay.hwh"
cp -f "$ROOT_DIR/overlay_manifest.json" "$OUT_DIR/overlay_manifest.json"
python3 "$ROOT_DIR/scripts/sync_manifest_offsets.py" --check \
  --manifest "$OUT_DIR/overlay_manifest.json" \
  --hwh "$OUT_DIR/snn_overlay.hwh"

echo "[pynq_z2] overlay artifacts written to $OUT_DIR"
