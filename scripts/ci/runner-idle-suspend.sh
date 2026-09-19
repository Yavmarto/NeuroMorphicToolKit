#!/usr/bin/env bash
# runner-idle-suspend.sh — put the runner machine back to sleep once it is idle.
#
# Runs on the runner host itself, including inside WSL2: a WSL distro can invoke
# Windows binaries, so the suspend call goes through powrprof.dll. The host
# sleeps in S3, which WSL2 survives, so the runner service is still registered
# and listening when runner-wake.sh wakes it again.
#
# Idle means all three of: no Runner.Worker process (no job executing), no job
# queued for our labels, and the machine has been awake for at least
# MIN_AWAKE_MINUTES. The last one matters because the runner takes a few seconds
# after wake to claim a job — without it the machine can sleep in the gap
# between the wake and the job starting.
#
# Usage: runner-idle-suspend.sh [--once] [--dry-run] [--config FILE]
#
# Config file (shell syntax, chmod 600; the same file runner-wake.sh uses is
# fine, and GITHUB_TOKEN may be omitted here to skip the queue check):
#   GITHUB_REPO="Yavmarto/NeuroMorphicToolKit"
#   GITHUB_TOKEN="github_pat_..."
#   WAKE_LABELS="nmtk-win,nmtk-linux"
#   IDLE_MINUTES=10
#   MIN_AWAKE_MINUTES=3
set -euo pipefail

CONFIG="/etc/nmtk-runner-wake.conf"
ONCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --config) CONFIG="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

IDLE_MINUTES="${IDLE_MINUTES:-10}"
MIN_AWAKE_MINUTES="${MIN_AWAKE_MINUTES:-3}"
CHECK_SECONDS="${CHECK_SECONDS:-60}"
STATE_FILE="${STATE_FILE:-/tmp/nmtk-runner-idle-ticks}"
WAKE_LABELS="${WAKE_LABELS:-}"

log() { printf '%s runner-idle: %s\n' "$(date -Is)" "$*"; }

job_running() {
  pgrep -f 'Runner\.Worker' >/dev/null 2>&1
}

# Skipped when no token is configured — the Runner.Worker check alone is enough
# to avoid interrupting a running job, this only avoids sleeping while work is
# still waiting to be claimed.
queue_pending() {
  [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_REPO:-}" ] || return 1
  command -v curl >/dev/null && command -v jq >/dev/null || return 1
  local count
  count="$(curl -fsS \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$GITHUB_REPO/actions/runs?status=queued&per_page=10" \
    | jq '.workflow_runs | length' 2>/dev/null || echo 0)"
  [ "${count:-0}" -gt 0 ]
}

awake_minutes() {
  awk '{printf "%d\n", $1 / 60}' /proc/uptime
}

suspend_host() {
  if [ "$DRY_RUN" = true ]; then
    log "[dry run] would suspend now"
    return 0
  fi
  sync
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    # WSL2 has no power management of its own; suspend the Windows host through
    # interop. `systemctl suspend` inside the distro is a no-op here.
    local rundll="/mnt/c/Windows/System32/rundll32.exe"
    [ -x "$rundll" ] || { log "ERROR: $rundll not found — is WSL interop enabled?"; return 1; }
    log "suspending Windows host"
    "$rundll" powrprof.dll,SetSuspendState 0,1,0
  else
    log "suspending host"
    systemctl suspend
  fi
}

check_once() {
  local ticks=0
  [ -f "$STATE_FILE" ] && ticks="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"

  if [ "$(awake_minutes)" -lt "$MIN_AWAKE_MINUTES" ]; then
    log "awake for less than ${MIN_AWAKE_MINUTES}m — holding"
    echo 0 > "$STATE_FILE"
    return 0
  fi

  if job_running; then
    log "job in progress — holding"
    echo 0 > "$STATE_FILE"
    return 0
  fi

  if queue_pending; then
    log "work still queued — holding"
    echo 0 > "$STATE_FILE"
    return 0
  fi

  ticks=$((ticks + 1))
  echo "$ticks" > "$STATE_FILE"
  local minutes=$((ticks * CHECK_SECONDS / 60))
  if [ "$minutes" -ge "$IDLE_MINUTES" ]; then
    log "idle for ${minutes}m (threshold ${IDLE_MINUTES}m)"
    echo 0 > "$STATE_FILE"
    suspend_host
  else
    log "idle for ${minutes}m of ${IDLE_MINUTES}m"
  fi
}

if [ "$ONCE" = true ]; then
  check_once
else
  while true; do
    check_once || log "check failed (will retry)"
    sleep "$CHECK_SECONDS"
  done
fi
