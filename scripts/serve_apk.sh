#!/usr/bin/env bash
# serve_apk.sh — Build the NMTK Flutter launcher APK and serve it over LAN.
#
# Usage:
#   scripts/serve_apk.sh [OPTIONS]
#
# Options:
#   --debug        Build a debug APK instead of release (default: release)
#   --skip-build   Skip the flutter build step; serve an existing APK
#   --port PORT    HTTP port (default: 8765)
#   -h, --help     Show this help message
#
# Examples:
#   scripts/serve_apk.sh
#   scripts/serve_apk.sh --debug
#   scripts/serve_apk.sh --skip-build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_DIR="$REPO_ROOT/nmtk/neuro_toolkit"
APK_OUTPUT_DIR="$FLUTTER_DIR/build/app/outputs/flutter-apk"
DEFAULT_PORT=8765

BUILD_MODE="release"
SKIP_BUILD=false
PORT="$DEFAULT_PORT"

usage() {
  sed -n '2,15p' "$0" | sed 's/^# //' | sed 's/^#//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      BUILD_MODE="debug"
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --port)
      PORT="${2:?--port requires a value}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but was not found on PATH." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required but was not found on PATH." >&2
  exit 1
fi

resolve_lan_ip() {
  python3 - <<'PY'
import re
import socket
import subprocess

SKIP_PREFIXES = ("lo", "docker", "br-", "veth", "utun", "vmnet", "gif", "stf")


def is_skipped(name):
    return name in {"lo", "lo0"} or any(name.startswith(p) for p in SKIP_PREFIXES)


def outbound_ip():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        ip = probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()
    if ip and not ip.startswith("127."):
        return ip
    return None


def interface_ips():
    try:
        output = subprocess.check_output(["ifconfig"], text=True, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        return []
    ips = []
    current = ""
    for line in output.splitlines():
        if line and not line.startswith(("\t", " ")):
            current = line.split(":", 1)[0]
        if is_skipped(current):
            continue
        match = re.search(r"\binet (\d+\.\d+\.\d+\.\d+)\b", line)
        if match:
            ip = match.group(1)
            if not ip.startswith("127."):
                ips.append(ip)
    return ips


ip = outbound_ip()
if ip:
    print(ip)
    raise SystemExit(0)

for candidate in interface_ips():
    print(candidate)
    raise SystemExit(0)

print("127.0.0.1")
PY
}

apk_filename() {
  if [ "$BUILD_MODE" = "debug" ]; then
    printf '%s\n' "app-debug.apk"
  else
    printf '%s\n' "app-release.apk"
  fi
}

free_port() {
  local port="$1"
  local pids
  pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -z "$pids" ]; then
    return 0
  fi
  echo "Port $port is in use; stopping existing listener(s): $pids"
  # ponytail: kills whatever holds the port; upgrade path is a PID file for our own server only.
  kill $pids 2>/dev/null || true
  sleep 0.5
  if lsof -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Failed to free port $port." >&2
    exit 1
  fi
}

print_download_url() {
  local url="$1"
  printf '\n'
  printf 'Download URL (tap to open on phone):\n'
  printf '%s\n' "$url"
  printf '\n'
}

print_qr_code() {
  local url="$1"
  if command -v qrencode >/dev/null 2>&1; then
    printf 'QR code:\n'
    qrencode -t ANSIUTF8 "$url"
    printf '\n'
  else
    printf 'QR code: qrencode is not installed (brew install qrencode). Use the URL above.\n\n'
  fi
}

LAN_IP="$(resolve_lan_ip)"
APK_NAME="$(apk_filename)"
APK_PATH="$APK_OUTPUT_DIR/$APK_NAME"

if [ "$SKIP_BUILD" = false ]; then
  echo "Building $BUILD_MODE APK from $FLUTTER_DIR ..."
  (
    cd "$FLUTTER_DIR"
    if [ "$BUILD_MODE" = "debug" ]; then
      flutter build apk --debug
    else
      flutter build apk --release
    fi
  )
fi

if [ ! -f "$APK_PATH" ]; then
  echo "APK not found at $APK_PATH" >&2
  echo "Run without --skip-build, or build manually from nmtk/neuro_toolkit." >&2
  exit 1
fi

free_port "$PORT"

DOWNLOAD_URL="http://${LAN_IP}:${PORT}/${APK_NAME}"

echo "Serving $APK_PATH on 0.0.0.0:$PORT (LAN IP: $LAN_IP)"
print_download_url "$DOWNLOAD_URL"
print_qr_code "$DOWNLOAD_URL"
echo "Press Ctrl+C to stop."

cd "$APK_OUTPUT_DIR"
exec python3 -m http.server "$PORT" --bind 0.0.0.0
