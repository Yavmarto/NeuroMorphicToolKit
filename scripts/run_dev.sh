#!/usr/bin/env bash
# run_dev.sh — thin orchestrator for the NMTK local dev stack.
#
# Delegates to focused sub-scripts in scripts/dev/:
#   lib.sh              — shared helper functions
#   reserve_ports.sh    — free control-API and suite-API ports
#   start_jupyter.sh    — start the Jupyter server
#   start_control_api.sh — start the launcher control (FastAPI) service
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Global base state (required by sub-scripts before sourcing).
# ---------------------------------------------------------------------------
CONTROL_API_PORT="${NMTK_CONTROL_API_PORT:-${LAUNCHER_CONTROL_PORT:-8090}}"
LAUNCHER_CONTROL_PORT="${LAUNCHER_CONTROL_PORT:-8090}"

# ---------------------------------------------------------------------------
# Source sub-scripts (defines all functions; does not execute side-effects).
# ---------------------------------------------------------------------------
source "$SCRIPT_DIR/dev/lib.sh"
source "$SCRIPT_DIR/dev/reserve_ports.sh"
source "$SCRIPT_DIR/dev/start_jupyter.sh"
source "$SCRIPT_DIR/dev/start_control_api.sh"

# ---------------------------------------------------------------------------
# Resolve prerequisites.
# ---------------------------------------------------------------------------
PYTHON3=""
if ! PYTHON3="$(find_python3)"; then
  echo "ERROR: Python 3 not found. Install Python 3 or activate a conda environment that provides it." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter command not found. Please install the Flutter SDK and ensure it is in your PATH." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Global state.
# ---------------------------------------------------------------------------
FLUTTER_DEVICE=""
USE_DOCKER="false"
CONTROL_API_PID=""
JUPYTER_PID=""
# CONTROL_API_BIND_HOST and CONTROL_API_PUBLIC_HOST are only used in the
# pure-local branch (no --docker, no --remote-host).
CONTROL_API_BIND_HOST="127.0.0.1"
CONTROL_API_PUBLIC_HOST="127.0.0.1"
SUITE_API_URL=""
REMOTE_HOST_IP=""

usage() {
  cat <<'EOF'
Usage: ./scripts/run_dev.sh --flutter-device <device> [options]

Options:
  --flutter-device <device>  Desktop Flutter target to run.
  --docker                   Use Docker for the backend services (starts all containers).
  --remote-host <ip>         Use an external remote host for the backend.
EOF
}

cleanup() {
  if [ -n "$CONTROL_API_PID" ] && kill -0 "$CONTROL_API_PID" 2>/dev/null; then
    kill "$CONTROL_API_PID" 2>/dev/null || true
  fi
  if [ -n "$JUPYTER_PID" ] && kill -0 "$JUPYTER_PID" 2>/dev/null; then
    kill "$JUPYTER_PID" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Parse arguments.
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --flutter-device)
      FLUTTER_DEVICE="${2:-}"
      shift 2
      ;;
    --docker)
      USE_DOCKER="true"
      shift
      ;;
    --remote-host)
      REMOTE_HOST_IP="$2"
      shift 2
      ;;
    --native-only)
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$FLUTTER_DEVICE" ]; then
  echo "--flutter-device is required" >&2
  usage >&2
  exit 1
fi

trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Resolve runtime context.
# ---------------------------------------------------------------------------
TARGET_PLATFORM="$(resolve_flutter_target_platform "$FLUTTER_DEVICE")"
HOST_IP="$(resolve_host_ip)"

if [[ "$TARGET_PLATFORM" == android* || "$TARGET_PLATFORM" == ios* || "$FLUTTER_DEVICE" == "ios" ]]; then
  CONTROL_API_BIND_HOST="0.0.0.0"
  CONTROL_API_PUBLIC_HOST="$HOST_IP"
  if [[ -z "$REMOTE_HOST_IP" ]]; then
    SUITE_API_URL="http://$CONTROL_API_PUBLIC_HOST:9000"
  fi
fi

if [[ -n "$REMOTE_HOST_IP" ]]; then
  SUITE_API_URL="http://$REMOTE_HOST_IP:9000"
fi

# ---------------------------------------------------------------------------
# --- SECTION: Docker ---
# ---------------------------------------------------------------------------
if [[ "$USE_DOCKER" == "true" ]]; then
  echo "------------------------------------------------------------"
  echo "==> Starting full Docker stack..."
  echo "------------------------------------------------------------"
  # Optional: NMTK_DOCKER_PRUNE=1 runs builder prune first (slower; use after disk-full builds).
  if [[ "${NMTK_DOCKER_PRUNE:-}" == "1" ]]; then
    echo "==> Pruning stale build cache (keeping 20GB most-recent)..."
    docker builder prune -f --keep-storage=20GB
  fi
  docker compose up --build -d
fi

CONTROL_API_URL=""

# ---------------------------------------------------------------------------
# --- SECTION: Backend startup (Docker / remote / local) ---
# ---------------------------------------------------------------------------
if [[ "$USE_DOCKER" == "true" ]]; then
  # Docker Compose manages both suite_api and launcher-control.
  # Always poll via loopback — the host machine may not route to its own LAN IP.
  _poll_url="http://localhost:${LAUNCHER_CONTROL_PORT:-8090}"
  # Resolve the URL that the Flutter app will use to reach the control service.
  if [[ "$TARGET_PLATFORM" == android* || "$TARGET_PLATFORM" == ios* || "$FLUTTER_DEVICE" == "ios" ]]; then
    CONTROL_API_URL="http://$HOST_IP:${LAUNCHER_CONTROL_PORT:-8090}"
  else
    CONTROL_API_URL="http://localhost:${LAUNCHER_CONTROL_PORT:-8090}"
  fi
  # Docker Compose already started the container; poll via loopback.
  wait_for_control_api "$_poll_url"

elif [[ -n "$REMOTE_HOST_IP" ]]; then
  # Backend is on a remote server (docker-ex targets).
  CONTROL_API_URL="http://$REMOTE_HOST_IP:${LAUNCHER_CONTROL_PORT:-8090}"
  echo "==> Using remote launcher control API at $CONTROL_API_URL"
  wait_for_control_api "$CONTROL_API_URL"

else
  # --- SECTION: Ports ---
  reserve_suite_api_port

  # --- SECTION: Jupyter ---
  # Start Jupyter before control API so suite_api inherits JUPYTER_* env.
  start_jupyter_server
  # Jupyter and neurocnl backend must share the same notebook directory.
  export JUPYTER_WORKER_URL="${JUPYTER_WORKER_URL:-http://127.0.0.1:${JUPYTER_PORT:-8008}}"
  export JUPYTER_NOTEBOOK_DIR="${JUPYTER_NOTEBOOK_DIR:-$HOME/nmtk_notebooks}"

  # --- SECTION: Control API ---
  start_control_api "$CONTROL_API_BIND_HOST" "true" ""
  CONTROL_API_URL="http://$CONTROL_API_PUBLIC_HOST:$CONTROL_API_PORT"
fi

# ---------------------------------------------------------------------------
# --- SECTION: Flutter launcher ---
# ---------------------------------------------------------------------------
echo "------------------------------------------------------------"
echo "==> Starting NeuroToolkit launcher on $FLUTTER_DEVICE"
echo "------------------------------------------------------------"
echo "==> HOST IP: $HOST_IP"
if [[ -n "$SUITE_API_URL" ]]; then
  echo "==> Using remote-accessible control API: $CONTROL_API_URL"
  echo "==> Using remote-accessible suite API:   $SUITE_API_URL"
  echo "    (If your phone cannot connect, ensure it is on the same WiFi as $HOST_IP)"
fi

cd "$REPO_ROOT/nmtk/neuro_toolkit"
flutter_args=(
  run
  -d "$FLUTTER_DEVICE"
)
if [[ "$USE_DOCKER" == "true" || -n "$REMOTE_HOST_IP" ]]; then
  # Explicit target requested via --docker/--remote-host: force the app onto
  # it. For the plain local branch, leave this unset so the app falls back to
  # its own remembered host / connect screen instead of a stale local default.
  flutter_args+=(
    --dart-define="NMTK_CONTROL_API_BASE_URL=$CONTROL_API_URL"
    --dart-define="NMTK_CONTROL_API_PORT=${LAUNCHER_CONTROL_PORT:-8090}"
  )
fi
if [[ -n "$SUITE_API_URL" ]]; then
  flutter_args+=(--dart-define="SUITE_API_URL=$SUITE_API_URL")
fi
if [[ -n "$REMOTE_HOST_IP" ]]; then
  flutter_args+=(--dart-define="NMTK_SERVICES_HOST=$REMOTE_HOST_IP")
elif [[ "$USE_DOCKER" == "true" ]] && \
     [[ "$TARGET_PLATFORM" == android* || "$TARGET_PLATFORM" == ios* || "$FLUTTER_DEVICE" == "ios" ]]; then
  # Docker on mobile: tell Flutter the host IP for direct suite_api access
  flutter_args+=(--dart-define="NMTK_SERVICES_HOST=$HOST_IP")
fi
flutter "${flutter_args[@]}"
