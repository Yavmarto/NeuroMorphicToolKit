#!/bin/bash
# Override webtop's default XFCE session to run NMTK as a single-app kiosk.
# KasmVNC expects DISPLAY :1 and an X server already running (handled by webtop init).

NMTK_BIN=/app/nmtk/nmtk/neuro_toolkit/build/linux/x64/release/bundle/neuro_toolkit

if [ ! -f "$NMTK_BIN" ]; then
    echo "ERROR: NMTK binary not found at $NMTK_BIN" >&2
    exit 1
fi

export DISPLAY=:1
exec "$NMTK_BIN"
