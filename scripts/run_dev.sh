#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Resolve a Python 3 interpreter.
# ---------------------------------------------------------------------------
find_python3() {
  local cmd
  for cmd in python3 python; do
    if command -v "$cmd" >/dev/null 2>&1; then
      if "$cmd" -c "import sys; exit(0 if sys.version_info.major == 3 else 1)" 2>/dev/null; then
        printf '%s\n' "$cmd"
        return 0
      fi
    fi
  done
  if [ -n "${CONDA_PREFIX:-}" ] && [ -x "${CONDA_PREFIX}/bin/python" ]; then
    if "${CONDA_PREFIX}/bin/python" -c "import sys; exit(0 if sys.version_info.major == 3 else 1)" 2>/dev/null; then
      printf '%s\n' "${CONDA_PREFIX}/bin/python"
      return 0
    fi
  fi
  return 1
}

PYTHON3=""
if ! PYTHON3="$(find_python3)"; then
  echo "ERROR: Python 3 not found. Install Python 3 or activate a conda environment that provides it." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter command not found. Please install the Flutter SDK and ensure it is in your PATH." >&2
  exit 1
fi

FLUTTER_DEVICE=""
USE_DOCKER="false"
DOCKER_PROFILE="default"
CONTROL_API_PORT="${NMTK_CONTROL_API_PORT:-8090}"
CONTROL_API_PID=""
CONTROL_API_BIND_HOST="127.0.0.1"
CONTROL_API_PUBLIC_HOST="127.0.0.1"
SUITE_API_URL=""
REMOTE_HOST_IP=""

usage() {
  cat <<'EOF'
Usage: ./scripts/run_dev.sh --flutter-device <device> [options]

Options:
  --flutter-device <device>  Desktop Flutter target to run.
  --docker                   Use Docker for the backend services.
  --profile <name>           Docker profile to use (e.g., physics, hardware, full).
  --remote-host <ip>         Use an external remote host for the backend.
EOF
}


cleanup() {
  if [ -n "$CONTROL_API_PID" ] && kill -0 "$CONTROL_API_PID" 2>/dev/null; then
    kill "$CONTROL_API_PID" 2>/dev/null || true
  fi
}

is_port_in_use() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}


resolve_host_ip() {
  "$PYTHON3" - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("8.8.8.8", 80))
    print(s.getsockname()[0])
except OSError:
    print("127.0.0.1")
finally:
    s.close()
PY
}


resolve_flutter_target_platform() {
  local target_id="$1"
  local py_script='
import json
import sys

target_id = sys.argv[1]
try:
    devices = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit(0)

for device in devices:
    if str(device.get("id", "")) == target_id:
        print(str(device.get("targetPlatform", "")))
        break
else:
    print("")
'
  flutter devices --machine 2>/dev/null | "$PYTHON3" -c "$py_script" "$target_id" || echo ""
}


wait_for_suite_api() {
  local control_url="$1"
  local timeout_secs=150
  local start
  start=$(date +%s)

  echo "==> Waiting for suite_api to be ready (timeout ${timeout_secs}s)..."
  while true; do
    local elapsed=$(( $(date +%s) - start ))
    if [ "$elapsed" -ge "$timeout_secs" ]; then
      echo "==> suite_api did not become ready within ${timeout_secs}s; continuing" >&2
      return 0
    fi

    local status
    status=$("$PYTHON3" - "$control_url" 2>/dev/null <<'PY'
import json, sys
import urllib.request, urllib.error
try:
    with urllib.request.urlopen(sys.argv[1] + "/health", timeout=2) as r:
        d = json.loads(r.read())
        print(str(d.get("suiteApiStatus") or "").strip())
except Exception:
    print("")
PY
)

    case "$status" in
      ready|disabled)
        echo "==> suite_api is ${status}"
        return 0
        ;;
      preflight_failed|failed)
        echo "==> suite_api reported preflight failure; starting Flutter anyway" >&2
        return 0
        ;;
    esac
    sleep 1
  done
}


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
    --profile)
      DOCKER_PROFILE="${2:-default}"
      shift 2
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

if [[ "$USE_DOCKER" == "true" ]]; then
  echo "------------------------------------------------------------"
  echo "==> Starting Docker containers (profile: $DOCKER_PROFILE)"
  if [[ "$DOCKER_PROFILE" == "default" ]]; then
    echo "    (Default profile starts only the suite_api container.)"
  else
    echo "    (Additional worker containers are enabled by the selected profile.)"
  fi
  echo "------------------------------------------------------------"
  if [[ "$DOCKER_PROFILE" == "default" ]]; then
    docker compose up --build -d
  elif [[ "$DOCKER_PROFILE" == "all" ]]; then
    ALL_PROFILES=$(docker compose config --profiles | tr '\n' ',' | sed 's/,$//')
    NEUROCNL_LAVA_WORKER_URL="${NEUROCNL_LAVA_WORKER_URL:-http://lava-backend:8012}" \
      COMPOSE_PROFILES="$ALL_PROFILES" docker compose up --build -d
  elif [[ "$DOCKER_PROFILE" == "hardware" ]]; then
    NEUROCNL_LAVA_WORKER_URL="${NEUROCNL_LAVA_WORKER_URL:-http://lava-backend:8012}" \
      docker compose --profile "$DOCKER_PROFILE" up --build -d
  else
    docker compose --profile "$DOCKER_PROFILE" up --build -d
  fi
fi

CONTROL_API_URL=""
# Only reserve suite api port if NOT using docker and NOT using remote host
if [[ "$USE_DOCKER" == "false" ]] && [[ -z "$REMOTE_HOST_IP" ]]; then
  reserve_suite_api_port
fi

MANAGE_SUITE_API="true"
if [[ "$USE_DOCKER" == "true" ]] || [[ -n "$REMOTE_HOST_IP" ]]; then
  MANAGE_SUITE_API="false"
fi

start_control_api "$CONTROL_API_BIND_HOST" "$MANAGE_SUITE_API" "$REMOTE_HOST_IP"
CONTROL_API_URL="http://$CONTROL_API_PUBLIC_HOST:$CONTROL_API_PORT"

if [[ -z "$REMOTE_HOST_IP" ]]; then
  wait_for_suite_api "$CONTROL_API_URL"
else
  echo "==> Using remote backend at $REMOTE_HOST_IP; skipping local suite_api readiness check."
fi

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
  --dart-define="NMTK_CONTROL_API_BASE_URL=$CONTROL_API_URL"
  --dart-define="NMTK_CONTROL_API_PORT=$CONTROL_API_PORT"
)
if [[ -n "$SUITE_API_URL" ]]; then
  flutter_args+=(--dart-define="SUITE_API_URL=$SUITE_API_URL")
fi
flutter "${flutter_args[@]}"
