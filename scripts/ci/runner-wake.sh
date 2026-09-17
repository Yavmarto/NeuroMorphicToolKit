#!/usr/bin/env bash
# runner-wake.sh — wake a sleeping self-hosted runner when a job needs it.
#
# Runs on an always-on machine on the same LAN as the runner (the dev backend
# box is the obvious host). A Wake-on-LAN magic packet cannot come from GitHub:
# it has to be sent from inside the broadcast domain, so something local must
# poll for queued work. One HTTP call every 30 s is enough — GitHub keeps a job
# queued for up to 24 h waiting on a matching runner, and the machine is awake
# and picking work up well inside a minute.
#
# Usage: runner-wake.sh [--once] [--config FILE]
#   --once     poll a single time and exit (what the systemd timer uses)
#   --config   defaults to /etc/nmtk-runner-wake.conf
#
# Config file (shell syntax, chmod 600 — it holds a token):
#   GITHUB_REPO="Yavmarto/NeuroMorphicToolKit"
#   GITHUB_TOKEN="github_pat_..."   # fine-grained, Actions: read-only
#   RUNNER_MAC="a4:bb:6d:11:22:33"  # wired NIC of the sleeping machine
#   RUNNER_HOST="203.0.113.91"      # used to test whether it is already awake
#   WAKE_LABELS="nmtk-win,nmtk-linux"
#   BROADCAST="203.0.113.255"       # subnet broadcast; more reliable than
#                                   # 255.255.255.255 on some switches
set -euo pipefail

CONFIG="/etc/nmtk-runner-wake.conf"
ONCE=false
POLL_SECONDS="${POLL_SECONDS:-30}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=true; shift ;;
    --config) CONFIG="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

: "${GITHUB_REPO:?GITHUB_REPO is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${RUNNER_MAC:?RUNNER_MAC is required}"
WAKE_LABELS="${WAKE_LABELS:-}"
RUNNER_HOST="${RUNNER_HOST:-}"
BROADCAST="${BROADCAST:-255.255.255.255}"
WOL_PORT="${WOL_PORT:-9}"
WAKE_TIMEOUT="${WAKE_TIMEOUT:-120}"

for tool in curl jq python3; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

log() { printf '%s runner-wake: %s\n' "$(date -Is)" "$*"; }

api() {
  curl -fsS \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$GITHUB_REPO/$1"
}

# Prints the number of queued jobs whose requested labels include one of
# WAKE_LABELS. Jobs targeting GitHub-hosted runners are also briefly queued, so
# filtering on the label is what keeps this from waking the machine for work it
# would never run.
queued_for_us() {
  local runs total=0 run_id count
  runs="$(api "actions/runs?status=queued&per_page=30" | jq -r '.workflow_runs[].id')"
  for run_id in $runs; do
    count="$(api "actions/runs/$run_id/jobs?per_page=100" \
      | jq --arg labels "$WAKE_LABELS" '
          ($labels | split(",") | map(select(length > 0) | ascii_downcase)) as $want
          | [ .jobs[]
              | select(.status == "queued")
              | select([ .labels[] | ascii_downcase ] as $have
                       | any($want[]; . as $w | ($have | index($w)) != null))
            ] | length')"
    total=$((total + count))
  done
  echo "$total"
}

host_is_up() {
  [ -n "$RUNNER_HOST" ] || return 1
  ping -c 1 -W 2 "$RUNNER_HOST" >/dev/null 2>&1
}

# The magic packet is 6 bytes of 0xFF followed by the MAC repeated 16 times.
# Implemented here rather than depending on wakeonlan/etherwake being installed.
send_magic_packet() {
  python3 - "$RUNNER_MAC" "$BROADCAST" "$WOL_PORT" <<'PY'
import socket
import sys

mac, broadcast, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
raw = bytes.fromhex(mac.replace(":", "").replace("-", ""))
if len(raw) != 6:
    sys.exit(f"Not a MAC address: {mac}")
packet = b"\xff" * 6 + raw * 16
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
for _ in range(3):
    sock.sendto(packet, (broadcast, port))
sock.close()
PY
}

poll_once() {
  local pending
  pending="$(queued_for_us)"
  [ "$pending" -gt 0 ] || return 0

  if host_is_up; then
    log "$pending job(s) queued, runner host already awake"
    return 0
  fi

  log "$pending job(s) queued for [$WAKE_LABELS] — sending WoL to $RUNNER_MAC"
  send_magic_packet

  [ -n "$RUNNER_HOST" ] || return 0
  local waited=0
  while [ "$waited" -lt "$WAKE_TIMEOUT" ]; do
    if host_is_up; then
      log "runner host responded after ${waited}s"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  log "WARNING: runner host did not respond within ${WAKE_TIMEOUT}s"
}

if [ "$ONCE" = true ]; then
  poll_once
else
  while true; do
    poll_once || log "poll failed (will retry)"
    sleep "$POLL_SECONDS"
  done
fi
