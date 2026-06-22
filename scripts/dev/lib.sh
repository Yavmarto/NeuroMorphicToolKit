#!/usr/bin/env bash
# scripts/dev/lib.sh — shared helpers sourced by all dev sub-scripts.
# Do NOT execute directly; source it.
set -euo pipefail

# REPO_ROOT must be set by the caller before sourcing this file.
: "${REPO_ROOT:?REPO_ROOT must be set before sourcing lib.sh}"

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

# ---------------------------------------------------------------------------
# Check whether a TCP port is already bound.
# ---------------------------------------------------------------------------
is_port_in_use() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Resolve the LAN IP of this host via a UDP probe.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Resolve the target platform string for a Flutter device id.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Poll the control API /health until suite_api status is known.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Poll the launcher control API /health until it responds.
# ---------------------------------------------------------------------------
wait_for_control_api() {
  local url="$1"
  local timeout_secs=90
  local start
  start=$(date +%s)

  echo "==> Waiting for launcher control API at $url (timeout ${timeout_secs}s)..."
  while true; do
    local elapsed=$(( $(date +%s) - start ))
    if [ "$elapsed" -ge "$timeout_secs" ]; then
      echo "==> Launcher control API did not become ready within ${timeout_secs}s; continuing" >&2
      return 0
    fi

    if "$PYTHON3" - "$url" 2>/dev/null <<'PY'
import sys, urllib.request, urllib.error
try:
    urllib.request.urlopen(sys.argv[1] + "/health", timeout=2)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then
      echo "==> Launcher control API is ready"
      return 0
    fi
    sleep 2
  done
}
