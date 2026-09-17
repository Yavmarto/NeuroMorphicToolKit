#!/usr/bin/env bash
#
# Build and run the snn_overlay_v2 testbench with a plain host compiler.
#
# This does not need Vitis HLS and runs anywhere, so the engine's behaviour can
# be checked before anyone books time on the Linux synthesis box.  Vitis HLS
# runs the same testbench via `csim_design` in build_hls.tcl, using its own
# headers rather than hls/csim_compat.

set -euo pipefail

HLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$HLS_DIR/../build/csim}"
CXX="${CXX:-c++}"

mkdir -p "$BUILD_DIR"

# The HLS loop labels are unused under a host compiler; Vitis needs them.
"$CXX" -std=c++14 -O1 -Wall -Wno-unused-label -Wno-unknown-pragmas \
    -I "$HLS_DIR/csim_compat" \
    -I "$HLS_DIR" \
    -o "$BUILD_DIR/snn_overlay_engine_tb" \
    "$HLS_DIR/snn_overlay_engine.cpp" \
    "$HLS_DIR/snn_overlay_engine_tb.cpp"

"$BUILD_DIR/snn_overlay_engine_tb"
