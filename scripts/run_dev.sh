#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Resolve a Python 3 interpreter.  On conda-managed machines the interpreter
# is often named 'python' (not 'python3').  Try explicit names first, then
# fall back to the active conda prefix when PATH doesn't expose either name.
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

FLUTTER_DEVICE=""
WITH_WEB=0
WEB_PORT="${NMTK_WEB_PORT:-8088}"
WEB_PID=""
CONTROL_API_PORT="${NMTK_CONTROL_API_PORT:-8090}"
CONTROL_API_PID=""
CONTROL_API_BIND_HOST="127.0.0.1"
MODULE_LIST=(
  "neurocnl:8000"
  "Neurosim:8001"
  "Neurochip:8002"
  "Neurobench:8003"
  "Neurosense:8004"
  "Neurohub:8005"
)

usage() {
  cat <<'EOF'
Usage: ./scripts/run_dev.sh --flutter-device <device> [--with-web]

Options:
  --flutter-device <device>  Desktop Flutter target to run.
  --with-web                 Also build and serve the launcher web app on the LAN.
EOF
}

detect_lan_host() {
  if [ -n "${NMTK_LAN_HOST:-}" ]; then
    printf '%s\n' "$NMTK_LAN_HOST"
    return 0
  fi

  case "$(uname -s)" in
    Darwin)
      local default_iface
      default_iface="$(route get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
      if [ -n "$default_iface" ]; then
        local iface_ip
        iface_ip="$(ipconfig getifaddr "$default_iface" 2>/dev/null || true)"
        if [ -n "$iface_ip" ]; then
          printf '%s\n' "$iface_ip"
          return 0
        fi
      fi

      local fallback_iface
      for fallback_iface in en0 en1; do
        local fallback_ip
        fallback_ip="$(ipconfig getifaddr "$fallback_iface" 2>/dev/null || true)"
        if [ -n "$fallback_ip" ]; then
          printf '%s\n' "$fallback_ip"
          return 0
        fi
      done
      ;;
    Linux)
      local linux_ip
      linux_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
      if [ -n "$linux_ip" ]; then
        printf '%s\n' "$linux_ip"
        return 0
      fi
      ;;
  esac

  local private_ip
  private_ip="$(
    ifconfig 2>/dev/null |
      awk '
        $1 == "inet" {
          ip = $2
          if (
            ip !~ /^127\./ &&
            ip !~ /^169\.254\./ &&
            (
              ip ~ /^10\./ ||
              ip ~ /^192\.168\./ ||
              ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./
            )
          ) {
            print ip
            exit
          }
        }
      '
  )"
  if [ -n "$private_ip" ]; then
    printf '%s\n' "$private_ip"
    return 0
  fi

  return 1
}

cleanup() {
  if [ -n "$WEB_PID" ] && kill -0 "$WEB_PID" 2>/dev/null; then
    kill "$WEB_PID" 2>/dev/null || true
  fi
  if [ -n "$CONTROL_API_PID" ] && kill -0 "$CONTROL_API_PID" 2>/dev/null; then
    kill "$CONTROL_API_PID" 2>/dev/null || true
  fi
}

is_port_in_use() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

reserve_web_port() {
  local candidate_port="$WEB_PORT"
  while is_port_in_use "$candidate_port"; do
    candidate_port=$((candidate_port + 1))
  done

  if [ "$candidate_port" != "$WEB_PORT" ]; then
    echo "==> Port $WEB_PORT is already in use; using $candidate_port instead"
  fi

  WEB_PORT="$candidate_port"
}

reserve_control_api_port() {
  local candidate_port="$CONTROL_API_PORT"
  while is_port_in_use "$candidate_port"; do
    candidate_port=$((candidate_port + 1))
  done

  if [ "$candidate_port" != "$CONTROL_API_PORT" ]; then
    echo "==> Port $CONTROL_API_PORT is already in use; using $candidate_port for launcher control API"
  fi

  CONTROL_API_PORT="$candidate_port"
}

build_submodules() {
  local api_host="${1:-}"

  chmod +x "$REPO_ROOT/scripts/build_module.sh"

  local entry mod port
  for entry in "${MODULE_LIST[@]}"; do
    mod="${entry%%:*}"
    port="${entry#*:}"
    if [ -n "$api_host" ]; then
      NMTK_API_HOST="$api_host" "$REPO_ROOT/scripts/build_module.sh" "$mod" "$port"
    else
      "$REPO_ROOT/scripts/build_module.sh" "$mod" "$port"
    fi
  done
}

build_launcher_web() {
  local control_api_base_url="${1:-}"

  echo "------------------------------------------------------------"
  echo "==> Building NeuroToolkit launcher web app"
  echo "------------------------------------------------------------"
  (
    cd "$REPO_ROOT/nmtk/neuro_toolkit"
    flutter build web --release --no-wasm-dry-run \
      --dart-define="NMTK_CONTROL_API_BASE_URL=$control_api_base_url" \
      --dart-define="NMTK_CONTROL_API_PORT=$CONTROL_API_PORT"
  )
}

start_control_api() {
  local host="$1"

  reserve_control_api_port

  local control_api_pythonpath="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}"
  local -a control_api_cmd=(
    "$PYTHON3"
    "$REPO_ROOT/scripts/launcher_control_service.py"
    --host "$host"
    --port "$CONTROL_API_PORT"
  )

  echo "------------------------------------------------------------"
  echo "==> Starting launcher control API on $host:$CONTROL_API_PORT"
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

start_launcher_web_server() {
  local lan_host="${1:-}"

  reserve_web_port

  echo "------------------------------------------------------------"
  echo "==> Serving launcher web build on 0.0.0.0:$WEB_PORT"
  if [ -n "$lan_host" ]; then
    echo "==> Open http://$lan_host:$WEB_PORT from your mobile browser"
  else
    echo "==> Set NMTK_LAN_HOST=<your-lan-ip> if auto-detection missed your host"
  fi
  echo "------------------------------------------------------------"

  (
    cd "$REPO_ROOT/nmtk/neuro_toolkit/build/web"
    "$PYTHON3" -m http.server "$WEB_PORT" --bind 0.0.0.0
  ) &
  WEB_PID=$!

  sleep 1
  if ! kill -0 "$WEB_PID" 2>/dev/null; then
    echo "==> Failed to start launcher web server on port $WEB_PORT" >&2
    exit 1
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --flutter-device)
      FLUTTER_DEVICE="${2:-}"
      shift 2
      ;;
    --with-web)
      WITH_WEB=1
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

LAN_HOST=""
DESKTOP_CONTROL_API_URL=""
WEB_CONTROL_API_URL=""
if [ "$WITH_WEB" -eq 1 ]; then
  LAN_HOST="$(detect_lan_host || true)"
  CONTROL_API_BIND_HOST="0.0.0.0"
  start_control_api "$CONTROL_API_BIND_HOST"
  WEB_CONTROL_API_URL="http://${LAN_HOST:-localhost}:$CONTROL_API_PORT"
  DESKTOP_CONTROL_API_URL="http://127.0.0.1:$CONTROL_API_PORT"
  build_submodules "$LAN_HOST"
  build_launcher_web "$WEB_CONTROL_API_URL"
  start_launcher_web_server "$LAN_HOST"
  export NMTK_UVICORN_HOST=0.0.0.0
else
  start_control_api "$CONTROL_API_BIND_HOST"
  DESKTOP_CONTROL_API_URL="http://127.0.0.1:$CONTROL_API_PORT"
  build_submodules
fi

echo "------------------------------------------------------------"
echo "==> Starting NeuroToolkit launcher on $FLUTTER_DEVICE"
echo "------------------------------------------------------------"
cd "$REPO_ROOT/nmtk/neuro_toolkit"
flutter run -d "$FLUTTER_DEVICE" \
  --dart-define="NMTK_CONTROL_API_BASE_URL=$DESKTOP_CONTROL_API_URL" \
  --dart-define="NMTK_CONTROL_API_PORT=$CONTROL_API_PORT"
