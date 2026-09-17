#!/bin/sh
# Seed the persistent notebooks volume with starter notebooks on first boot.
# Any notebook that already exists is left untouched so user edits survive restarts.
for f in /app/notebooks/*.ipynb; do
  [ -f "$f" ] || continue
  target="$JUPYTER_NOTEBOOK_DIR/$(basename "$f")"
  [ -f "$target" ] || cp "$f" "$target"
done

exec jupyter server \
  --config=/app/jupyter_server_config.py \
  --notebook-dir="${JUPYTER_NOTEBOOK_DIR}"
