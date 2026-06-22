#!/usr/bin/env bash
# scripts/dev/reserve_ports.sh — free ports used by the control API and suite API.
#
# Can be sourced by run_dev.sh (preferred) or executed standalone:
#   REPO_ROOT=/path/to/repo PYTHON3=python3 bash scripts/dev/reserve_ports.sh
set -euo pipefail

_RESERVE_PORTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When run standalone, bootstrap REPO_ROOT and PYTHON3 from the environment.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  REPO_ROOT="${REPO_ROOT:-$(cd "$_RESERVE_PORTS_DIR/../.." && pwd)}"
  PYTHON3="${PYTHON3:-python3}"
  source "$_RESERVE_PORTS_DIR/lib.sh"
fi

# CONTROL_API_PORT must be set by the caller (or exported before standalone use).
: "${CONTROL_API_PORT:?CONTROL_API_PORT must be set before sourcing reserve_ports.sh}"

# ---------------------------------------------------------------------------
# Reserve (free) the launcher control-API port.
# ---------------------------------------------------------------------------
reserve_control_api_port() {
  if is_port_in_use "$CONTROL_API_PORT"; then
    echo "==> Port $CONTROL_API_PORT is in use; freeing it..."
    # SIGTERM first so the launcher control service can terminate the suite_api child cleanly.
    lsof -ti:"$CONTROL_API_PORT" | xargs kill -TERM 2>/dev/null || true
    sleep 2
    if is_port_in_use "$CONTROL_API_PORT"; then
      lsof -ti:"$CONTROL_API_PORT" | xargs kill -9 2>/dev/null || true
      sleep 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# Reserve (free) the suite-API port.
# ---------------------------------------------------------------------------
reserve_suite_api_port() {
  local suite_port="${NMTK_SUITE_API_PORT:-9000}"
  if is_port_in_use "$suite_port"; then
    echo "==> Port $suite_port is in use; freeing it..."
    lsof -ti:"$suite_port" | xargs kill -TERM 2>/dev/null || true
    sleep 2
    if is_port_in_use "$suite_port"; then
      lsof -ti:"$suite_port" | xargs kill -9 2>/dev/null || true
      sleep 1
    fi
  fi
}

# When executed directly (not sourced), run both reservation functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  reserve_control_api_port
  reserve_suite_api_port
fi
