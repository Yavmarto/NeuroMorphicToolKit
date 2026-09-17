#!/usr/bin/env bash
# scripts/dev/start_jupyter.sh — start the Jupyter server for the Notebook step.
#
# Can be sourced by run_dev.sh (preferred) or executed standalone:
#   REPO_ROOT=/path/to/repo PYTHON3=python3 bash scripts/dev/start_jupyter.sh
#
# Exported env vars used by downstream processes:
#   JUPYTER_WORKER_URL  — e.g. http://127.0.0.1:8008
#   JUPYTER_NOTEBOOK_DIR — local notebook directory (created if absent)
#
# Side-effect when sourced: sets JUPYTER_PID in the calling shell.
set -euo pipefail

_START_JUPYTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When run standalone, bootstrap REPO_ROOT and PYTHON3 from the environment.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  REPO_ROOT="${REPO_ROOT:-$(cd "$_START_JUPYTER_DIR/../.." && pwd)}"
  PYTHON3="${PYTHON3:-python3}"
  source "$_START_JUPYTER_DIR/lib.sh"
  # Standalone: use a local variable so we don't trample the caller's JUPYTER_PID.
  JUPYTER_PID=""
fi

# ---------------------------------------------------------------------------
# Start the Jupyter server, or skip if already running on the target port.
# Writes the server PID to JUPYTER_PID (must be declared in calling scope).
# ---------------------------------------------------------------------------
start_jupyter_server() {
  local jupyter_dir="$REPO_ROOT/workers/jupyter_server"
  local notebook_dir="${JUPYTER_NOTEBOOK_DIR:-$HOME/nmtk_notebooks}"
  local jupyter_port="${JUPYTER_PORT:-8008}"

  # Skip if already listening on the Jupyter port.
  if is_port_in_use "$jupyter_port"; then
    echo "==> Jupyter already running on port $jupyter_port — skipping start"
    return 0
  fi

  # Resolve the jupyter executable: prefer the worker venv, fall back to system.
  local jupyter_cmd=""
  if [ -x "$jupyter_dir/.venv/bin/jupyter" ]; then
    jupyter_cmd="$jupyter_dir/.venv/bin/jupyter"
  elif command -v jupyter >/dev/null 2>&1; then
    jupyter_cmd="jupyter"
  else
    echo "==> WARNING: jupyter not found — Notebook step will show 'server unavailable'."
    echo "             Run:  cd $jupyter_dir && python -m venv .venv && .venv/bin/pip install -r requirements.txt"
    return 0
  fi

  mkdir -p "$notebook_dir"

  # Seed starter notebooks if not already present.
  for nb in "$jupyter_dir/notebooks/"*.ipynb; do
    [ -f "$nb" ] || continue
    local dest="$notebook_dir/$(basename "$nb")"
    [ -f "$dest" ] || cp "$nb" "$dest"
  done

  echo "==> Starting Jupyter server on port $jupyter_port (notebooks: $notebook_dir)"
  mkdir -p "$REPO_ROOT/logs"
  JUPYTER_NOTEBOOK_DIR="$notebook_dir" \
    "$jupyter_cmd" server \
      --config="$jupyter_dir/jupyter_server_config.py" \
      --notebook-dir="$notebook_dir" \
      > "$REPO_ROOT/logs/jupyter_server.log" 2>&1 &
  JUPYTER_PID=$!
  echo "==> Jupyter server started (pid $JUPYTER_PID, log: logs/jupyter_server.log)"
}

# When executed directly (not sourced), run start_jupyter_server.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  start_jupyter_server
fi
