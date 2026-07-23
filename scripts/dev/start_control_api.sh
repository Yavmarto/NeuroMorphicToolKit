#!/usr/bin/env bash
# scripts/dev/start_control_api.sh — launch the launcher control (FastAPI) service.
#
# Can be sourced by run_dev.sh (preferred) or executed standalone:
#   REPO_ROOT=/path/to/repo PYTHON3=python3 \
#   CONTROL_API_PORT=8090 bash scripts/dev/start_control_api.sh
#
# Side-effect when sourced: sets CONTROL_API_PID in the calling shell.
#
# Required variables (must be set in calling scope or environment):
#   REPO_ROOT            — repository root path
#   PYTHON3              — resolved Python 3 executable
#   CONTROL_API_PORT     — port for the control API
#   CONTROL_API_PID      — output variable; receives the PID of the spawned process
set -euo pipefail

_START_CTRL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When run standalone, bootstrap from the environment.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  REPO_ROOT="${REPO_ROOT:-$(cd "$_START_CTRL_DIR/../.." && pwd)}"
  PYTHON3="${PYTHON3:-python3}"
  CONTROL_API_PORT="${CONTROL_API_PORT:-8090}"
  source "$_START_CTRL_DIR/lib.sh"
  source "$_START_CTRL_DIR/reserve_ports.sh"
  CONTROL_API_PID=""
fi

# ---------------------------------------------------------------------------
# Start the launcher control API process.
#   $1 — bind host (e.g. 127.0.0.1 or 0.0.0.0)
#   $2 — "true"|"false" — whether the control service manages suite_api
#   $3 — optional external probe host (empty string to omit)
# ---------------------------------------------------------------------------
start_control_api() {
  local host="$1"
  local manage_suite_api="$2"
  local external_probe_host="${3:-}"

  reserve_control_api_port

  local control_api_pythonpath="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}"
  local -a control_api_cmd=(
    "$PYTHON3"
    "$REPO_ROOT/scripts/launcher_control_service.py"
    --host "$host"
    --port "$CONTROL_API_PORT"
  )

  if [[ "$manage_suite_api" == "false" ]]; then
    control_api_cmd+=(--no-manage-suite-api)
  fi

  if [[ -n "$external_probe_host" ]]; then
    control_api_cmd+=(--external-probe-host "$external_probe_host")
  fi

  echo "------------------------------------------------------------"
  echo "==> Starting launcher control API on $host:$CONTROL_API_PORT"
  if [[ "$manage_suite_api" == "false" ]]; then
    echo "    (Suite API management disabled — assuming external/docker start)"
  fi
  if [[ -n "$external_probe_host" ]]; then
    echo "    (External probe host: $external_probe_host)"
  fi
  echo "------------------------------------------------------------"

  NMTK_UVICORN_HOST="$host" PYTHONPATH="$control_api_pythonpath" "${control_api_cmd[@]}" &
  CONTROL_API_PID=$!

  sleep 1
  if ! kill -0 "$CONTROL_API_PID" 2>/dev/null; then
    set +e
    wait "$CONTROL_API_PID"
    local exit_code=$?
    set -e
    echo "==> Failed to start launcher control API on port $CONTROL_API_PORT (exit $exit_code)" >&2
    echo "==> Command: NMTK_UVICORN_HOST=\"$host\" PYTHONPATH=\"$control_api_pythonpath\" ${control_api_cmd[*]}" >&2
    exit 1
  fi
}

# When executed directly (not sourced), start with defaults.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  start_control_api "${CONTROL_API_BIND_HOST:-127.0.0.1}" "true" ""
fi
