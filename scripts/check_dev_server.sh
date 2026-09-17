#!/usr/bin/env bash
# check_dev_server.sh — Check whether everything on the dev server is running,
# and automatically restart any services that are stopped, unhealthy, or failing.
#
# Default target server: 203.0.113.90 (dev@203.0.113.90)
#
# Usage:
#   scripts/check_dev_server.sh [OPTIONS] [HOST]
#
# Options:
#   --check-only      Only report status; do not attempt to restart any service
#   --restart-all     Restart all services regardless of current status
#   --timeout SEC     HTTP probe timeout per service in seconds (default: 5)
#   --deploy-dir DIR  Remote deployment directory (default: ~/nmtk-deploy)
#   -h, --help        Show this help message
#
# Examples:
#   scripts/check_dev_server.sh
#   scripts/check_dev_server.sh 203.0.113.90
#   scripts/check_dev_server.sh dev@203.0.113.90 --check-only

set -euo pipefail

DEFAULT_IP="203.0.113.90"
DEFAULT_USER="dev"
TARGET_HOST=""
CHECK_ONLY=false
RESTART_ALL=false
PROBE_TIMEOUT=5
DEPLOY_DIR="${DEPLOY_DIR:-~/nmtk-deploy}"
SSH_TIMEOUT=8

# Terminal colors
if [ -t 1 ]; then
  C_RESET="\033[0m"
  C_GREEN="\033[32m"
  C_RED="\033[31m"
  C_YELLOW="\033[33m"
  C_BLUE="\033[34m"
  C_BOLD="\033[1m"
else
  C_RESET=""
  C_GREEN=""
  C_RED=""
  C_YELLOW=""
  C_BLUE=""
  C_BOLD=""
fi

log_info()    { printf "${C_BLUE}==>${C_RESET} %s\n" "$*"; }
log_success() { printf "  ${C_GREEN}[OK]${C_RESET}     %s\n" "$*"; }
log_warn()    { printf "  ${C_YELLOW}[WARN]${C_RESET}   %s\n" "$*"; }
log_down()    { printf "  ${C_RED}[DOWN]${C_RESET}   %s\n" "$*"; }
log_fixed()   { printf "  ${C_GREEN}[FIXED]${C_RESET}  %s\n" "$*"; }

usage() {
  sed -n '2,19p' "$0" | sed 's/^# //' | sed 's/^#//'
  exit 0
}

# Parse CLI arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only)
      CHECK_ONLY=true
      shift
      ;;
    --restart-all)
      RESTART_ALL=true
      shift
      ;;
    --timeout)
      shift
      [ $# -gt 0 ] || { echo "error: --timeout requires seconds" >&2; exit 1; }
      PROBE_TIMEOUT="$1"
      shift
      ;;
    --deploy-dir)
      shift
      [ $# -gt 0 ] || { echo "error: --deploy-dir requires a path" >&2; exit 1; }
      DEPLOY_DIR="$1"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [ -z "$TARGET_HOST" ]; then
        TARGET_HOST="$1"
        shift
      else
        echo "error: unknown argument: $1" >&2
        usage
      fi
      ;;
  esac
done

# Resolve target host: CLI arg -> REMOTE_HOST env -> DEV_BACKEND_HOST env -> default
if [ -z "$TARGET_HOST" ]; then
  TARGET_HOST="${REMOTE_HOST:-${DEV_BACKEND_HOST:-$DEFAULT_IP}}"
fi

# If target host is bare IP or hostname without user, prepend default user
if [[ "$TARGET_HOST" != *"@"* ]] && [ "$TARGET_HOST" != "localhost" ] && [ "$TARGET_HOST" != "127.0.0.1" ]; then
  SSH_TARGET="${DEFAULT_USER}@${TARGET_HOST}"
  REMOTE_IP="$TARGET_HOST"
elif [[ "$TARGET_HOST" == *"@"* ]]; then
  SSH_TARGET="$TARGET_HOST"
  REMOTE_IP="${TARGET_HOST#*@}"
else
  SSH_TARGET="localhost"
  REMOTE_IP="127.0.0.1"
fi

IS_LOCAL=false
if [ "$REMOTE_IP" = "127.0.0.1" ] || [ "$REMOTE_IP" = "localhost" ]; then
  IS_LOCAL=true
fi

# Run command on target (via SSH or locally)
run_cmd() {
  if $IS_LOCAL; then
    eval "$*"
  else
    # shellcheck disable=SC2029
    ssh -o ConnectTimeout="$SSH_TIMEOUT" \
        -o BatchMode=no \
        -o StrictHostKeyChecking=accept-new \
        -o ControlMaster=auto \
        -o ControlPath="/tmp/nmtk-ssh-%h-%p-%r" \
        -o ControlPersist=60s \
        "$SSH_TARGET" "$@"
  fi
}

run_probe() {
  run_cmd "$@" 2>/dev/null || true
}

echo ""
printf "${C_BOLD}NMTK Dev Server Health Check & Auto-Restart${C_RESET}\n"
printf "Target server: ${C_BLUE}%s${C_RESET} (IP: %s)\n\n" "$SSH_TARGET" "$REMOTE_IP"

# 1. Connectivity check
log_info "Testing connectivity to $SSH_TARGET..."
if ! $IS_LOCAL; then
  if ! ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$SSH_TARGET" "true" 2>/dev/null; then
    # Try interactive in case password/passphrase prompt is needed
    if ! run_cmd "true"; then
      log_down "Cannot reach $SSH_TARGET via SSH."
      echo ""
      echo "Troubleshooting:"
      echo "  1. Verify the dev server is powered on and connected to LAN (IP: $REMOTE_IP)."
      echo "  2. Test manual connection: ssh $SSH_TARGET"
      echo "  3. If using VPN or different subnet, check routes to $REMOTE_IP."
      exit 1
    fi
  fi
fi
log_success "Host connection established."

# 2. Check native systemd Akida service if present
log_info "Checking native system services..."
AKIDA_NATIVE=false
SYSTEMD_CHECK="$(run_probe "command -v systemctl >/dev/null 2>&1 && systemctl is-active neurochip.service 2>/dev/null || echo 'not-found'")"
SYSTEMD_CHECK="$(printf '%s' "$SYSTEMD_CHECK" | tr -d '\r\n')"

NEUROCHIP_SERVICE_DOWN=false
if [ "$SYSTEMD_CHECK" = "active" ]; then
  AKIDA_NATIVE=true
  log_success "neurochip.service (native BrainChip Akida): active"
elif [ "$SYSTEMD_CHECK" = "inactive" ] || [ "$SYSTEMD_CHECK" = "failed" ] || [ "$SYSTEMD_CHECK" = "deactivating" ]; then
  AKIDA_NATIVE=true
  NEUROCHIP_SERVICE_DOWN=true
  log_down "neurochip.service (native BrainChip Akida): $SYSTEMD_CHECK"
elif [ "$SYSTEMD_CHECK" = "not-found" ] || [ -z "$SYSTEMD_CHECK" ]; then
  # Check if unit exists but is stopped
  UNIT_EXISTS="$(run_probe "systemctl list-unit-files neurochip.service 2>/dev/null | grep -c neurochip.service || true")"
  UNIT_EXISTS="$(printf '%s' "$UNIT_EXISTS" | tr -d '[:space:]')"
  if [ "$UNIT_EXISTS" = "1" ]; then
    AKIDA_NATIVE=true
    NEUROCHIP_SERVICE_DOWN=true
    log_down "neurochip.service exists but is not active"
  else
    log_info "neurochip.service not installed (using containerized neurochip worker)"
  fi
fi

# 3. Detect container engine & compose setup
log_info "Checking container runtime in $DEPLOY_DIR..."
CONTAINER_ENGINE="$(run_probe "command -v docker >/dev/null 2>&1 && echo docker || (command -v podman >/dev/null 2>&1 && echo podman || echo '')")"
CONTAINER_ENGINE="$(printf '%s' "$CONTAINER_ENGINE" | tr -d '\r\n')"

if [ -z "$CONTAINER_ENGINE" ]; then
  log_down "Neither docker nor podman found on $SSH_TARGET."
  exit 1
fi
log_success "Container engine: $CONTAINER_ENGINE"

# Determine compose file flags
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.dev.yml"
if $AKIDA_NATIVE; then
  COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.akida-native.yml"
fi

# Fetch Akida API Key if Akida native
NEUROCHIP_API_KEY=""
if $AKIDA_NATIVE; then
  NEUROCHIP_API_KEY="$(run_probe "command -v nmtk-read-akida-key >/dev/null 2>&1 && sudo nmtk-read-akida-key 2>/dev/null || echo ''")"
  NEUROCHIP_API_KEY="$(printf '%s' "$NEUROCHIP_API_KEY" | tr -d '\r\n')"
fi

compose_cmd() {
  local subcmd="$1"
  run_cmd "cd $DEPLOY_DIR && \
    LAUNCHER_CONTROL_PORT=8090 \
    JUPYTER_PUBLIC_URL=http://${REMOTE_IP}:8008/lab \
    NEUROCHIP_HW_WORKER_API_KEY='${NEUROCHIP_API_KEY}' \
    $CONTAINER_ENGINE compose $COMPOSE_FILES $subcmd"
}

# 4. Probe HTTP health endpoints on the server
# Endpoint definitions: <service_name>|<port>|<path>|<expected_code>
SERVICES=(
  "suite_api|9000|/api/suite/health|200"
  "launcher-control|8090|/health|200"
  "jupyter-server|8008|/api/status|200"
  "neurobench-runner-worker|8003|/health|200"
  "neurocnl-physics-worker|8006|/health|200"
  "snn-mlir-compiler|8007|/health|200"
  "lava-backend|8012|/health|200"
)

# If not Akida native, check containerized neurochip-hw-worker
if ! $AKIDA_NATIVE; then
  SERVICES+=("neurochip-hw-worker|8002|/health|200")
fi

log_info "Probing services..."
DOWN_SERVICES=()

# Remote python probe script to check endpoints accurately from the dev host
REMOTE_PROBE_SCRIPT='
import sys, urllib.request, urllib.error

url = sys.argv[1]
timeout = float(sys.argv[2])
try:
    req = urllib.request.Request(url, headers={"User-Agent": "nmtk-health-checker"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        code = res.getcode()
        if 200 <= code < 400:
            print("OK")
            sys.exit(0)
        else:
            print(f"HTTP_{code}")
            sys.exit(1)
except urllib.error.HTTPError as e:
    print(f"HTTP_{e.code}")
    sys.exit(1)
except Exception as e:
    print("UNREACHABLE")
    sys.exit(2)
'

for item in "${SERVICES[@]}"; do
  IFS='|' read -r svc port path expected <<< "$item"
  url="http://127.0.0.1:${port}${path}"

  if $RESTART_ALL; then
    DOWN_SERVICES+=("$svc")
    log_warn "$svc (port $port): queued for restart (--restart-all)"
    continue
  fi

  probe_result="$(run_probe "python3 -c '$REMOTE_PROBE_SCRIPT' '$url' '$PROBE_TIMEOUT' 2>/dev/null || echo 'FAILED'")"
  probe_result="$(printf '%s' "$probe_result" | tr -d '\r\n')"

  if [ "$probe_result" = "OK" ]; then
    log_success "$svc (port $port): running & healthy"
  else
    log_down "$svc (port $port): $probe_result"
    DOWN_SERVICES+=("$svc")
  fi
done

# Check native neurochip service health endpoint if active
if $AKIDA_NATIVE; then
  akida_health="$(run_probe "python3 -c '$REMOTE_PROBE_SCRIPT' 'http://127.0.0.1:8002/health' '$PROBE_TIMEOUT' 2>/dev/null || echo 'FAILED'")"
  akida_health="$(printf '%s' "$akida_health" | tr -d '\r\n')"
  if [ "$akida_health" = "OK" ]; then
    log_success "neurochip hardware service (port 8002): running & healthy"
  else
    log_down "neurochip hardware service (port 8002): $akida_health"
    NEUROCHIP_SERVICE_DOWN=true
  fi
fi

# Summary check
TOTAL_DOWN=${#DOWN_SERVICES[@]}
if $NEUROCHIP_SERVICE_DOWN; then
  TOTAL_DOWN=$((TOTAL_DOWN + 1))
fi

if [ "$TOTAL_DOWN" -eq 0 ]; then
  echo ""
  printf "${C_GREEN}${C_BOLD}All dev server services are up and healthy!${C_RESET}\n\n"
  exit 0
fi

echo ""
log_warn "Detected $TOTAL_DOWN service(s) down or degraded."

if $CHECK_ONLY; then
  log_info "Check-only mode requested; exiting without restarting."
  exit 1
fi

# 5. Restart failed services
log_info "Restarting down services..."

# A. Restart native neurochip.service if needed
if $NEUROCHIP_SERVICE_DOWN; then
  log_info "Restarting native neurochip.service..."
  if run_cmd "sudo systemctl restart neurochip.service" 2>/dev/null; then
    sleep 2
    if [ "$(run_probe "systemctl is-active neurochip.service" | tr -d '\r\n')" = "active" ]; then
      log_fixed "neurochip.service restarted successfully."
    else
      log_warn "neurochip.service restart triggered; check journalctl -u neurochip.service"
    fi
  else
    log_warn "Could not restart neurochip.service (sudo permission needed)."
  fi
fi

# B. Restart down container services
if [ "${#DOWN_SERVICES[@]}" -gt 0 ]; then
  # If all or most container services are down, do a full `up -d`
  if [ "${#DOWN_SERVICES[@]}" -ge 4 ] || $RESTART_ALL; then
    log_info "Bringing up entire compose stack (up -d)..."
    compose_cmd "up -d"
  else
    for svc in "${DOWN_SERVICES[@]}"; do
      log_info "Restarting container service: $svc..."
      compose_cmd "restart $svc" || compose_cmd "up -d $svc"
    done
  fi

  # 6. Verify health after restart
  log_info "Waiting for restarted services to become healthy..."
  RETRY_TIMEOUT=60
  START_TIME=$(date +%s)
  STILL_DOWN=()

  for svc in "${DOWN_SERVICES[@]}"; do
    # Find matching port and path
    for item in "${SERVICES[@]}"; do
      IFS='|' read -r s port path expected <<< "$item"
      if [ "$s" = "$svc" ]; then
        url="http://127.0.0.1:${port}${path}"
        healthy=false
        while true; do
          res="$(run_probe "python3 -c '$REMOTE_PROBE_SCRIPT' '$url' 2 2>/dev/null || echo 'FAILED'")"
          res="$(printf '%s' "$res" | tr -d '\r\n')"
          if [ "$res" = "OK" ]; then
            healthy=true
            log_fixed "$svc (port $port) is now healthy."
            break
          fi
          current_time=$(date +%s)
          if [ $((current_time - START_TIME)) -ge $RETRY_TIMEOUT ]; then
            break
          fi
          sleep 2
        done

        if ! $healthy; then
          log_down "$svc (port $port) did not recover within ${RETRY_TIMEOUT}s."
          STILL_DOWN+=("$svc")
        fi
        break
      fi
    done
  done

  if [ "${#STILL_DOWN[@]}" -gt 0 ]; then
    echo ""
    log_down "Some services could not be recovered automatically: ${STILL_DOWN[*]}"
    echo "To inspect logs, run:"
    for s in "${STILL_DOWN[@]}"; do
      echo "  ssh $SSH_TARGET '$CONTAINER_ENGINE logs --tail 50 ${s}'"
    done
    echo ""
    exit 1
  fi
fi

echo ""
printf "${C_GREEN}${C_BOLD}All dev server services are now running and healthy!${C_RESET}\n\n"
exit 0
