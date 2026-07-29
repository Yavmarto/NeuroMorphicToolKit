#!/usr/bin/env bash
# dev_update.sh — daily driver: push local backend source to the dev host and do
# the minimum needed to make it live.
#
# Usage: scripts/dev_update.sh [OPTIONS]
#   --skip-tests           don't run the changed-module test suites first
#   --skip-jupyter-check   don't gate success on jupyter-server answering on :8008
#   --no-rebuild           sync only; warn instead of rebuilding
#   --force-rebuild SVC    rebuild SVC regardless of what changed (repeatable)
#   --dry-run              decide and print; change nothing, locally or remotely
#   --explain PATH...      print what each path would trigger, and exit. Needs no
#                          host — use it to check the table or ask "why did it
#                          rebuild that?"
#   --akida-native         force the akida-native overlay on
#   --no-akida-native      force it off (default is auto-detect)
#   --evict-ports          kill whatever else holds a stack port, then retry
#   --remove-orphans       also remove containers no compose file defines
#   -h | --help
#
# Env: REMOTE_HOST (default moosebuntu@192.168.2.51), DEPLOY_DIR,
#      CONTAINER_ENGINE, AKIDA_NATIVE (1/0 to skip detection)
#
# Why this exists: `docker-ex-deploy` rebuilds all 14 images for a one-line
# Python change, and a plain rsync silently does nothing for the services that
# have no bind mount. Neither is right, because the dev topology is not uniform —
# see the decide_actions() table.
#
# It needs no state file: rsync --itemize-changes reports exactly which paths
# differed from the host, which is by construction the set that changed since
# the last sync.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/dev/lib.sh
source "$REPO_ROOT/scripts/dev/lib.sh"   # also sets -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-moosebuntu@192.168.2.51}"
DEPLOY_DIR="${DEPLOY_DIR:-~/nmtk-deploy}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"
SSH_OPTS="${SSH_OPTS:--o ControlMaster=auto -o ControlPath=/tmp/nmtk-ssh-%h-%p-%r -o ControlPersist=60s}"
EXCLUDE_FILE="$REPO_ROOT/scripts/rsync-excludes.txt"
COMPOSE_ARGS="-f docker-compose.yml -f docker-compose.dev.yml"

SKIP_TESTS=false
SKIP_JUPYTER_CHECK=false
NO_REBUILD=false
DRY_RUN=false
EVICT_PORTS=false
REMOVE_ORPHANS=false
FORCED_SERVICES=()
EXPLAIN_PATHS=()
# unset = auto-detect; 1/0 = forced. See resolve_akida_native().
AKIDA_NATIVE="${AKIDA_NATIVE:-}"
AKIDA_DETECTED_VIA=""
NEUROCHIP_PORT=8002

PYTHON3="$(find_python3)" || { echo "error: no python3 found" >&2; exit 1; }

log()  { printf '==> %s\n' "$*"; }
warn() { printf '==> WARNING: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-tests)      SKIP_TESTS=true ;;
    --skip-jupyter-check) SKIP_JUPYTER_CHECK=true ;;
    --no-rebuild)      NO_REBUILD=true ;;
    --akida-native)    AKIDA_NATIVE=1 ;;
    --no-akida-native) AKIDA_NATIVE=0 ;;
    --evict-ports)     EVICT_PORTS=true ;;
    --remove-orphans)  REMOVE_ORPHANS=true ;;
    --force-rebuild) shift; [ $# -gt 0 ] || die "--force-rebuild needs a service name"
                     FORCED_SERVICES+=("$1") ;;
    --dry-run)       DRY_RUN=true ;;
    --explain)       shift; [ $# -gt 0 ] || die "--explain needs at least one path"
                     EXPLAIN_PATHS=("$@"); break ;;
    -h|--help)       sed -n '2,21p' "$0"; exit 0 ;;
    *)               die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

remote() {
  # SC2086: SSH_OPTS must word-split into separate flags.
  # SC2029: the command is deliberately assembled here and expanded remotely —
  # DEPLOY_DIR keeps its literal `~` so the remote shell resolves it.
  # shellcheck disable=SC2086,SC2029
  ssh $SSH_OPTS "$REMOTE_HOST" "$@"
}

# Read-only probe that never fails the script.
#
# `remote` cannot be used inside `x="$(...)"` for detection: lib.sh sets
# `pipefail`, so ssh's exit 255 becomes the status of the whole substitution and
# `set -e` kills the run with no diagnostic at all. Detection must degrade to an
# empty answer instead.
remote_probe() {
  # shellcheck disable=SC2086,SC2029
  ssh $SSH_OPTS "$REMOTE_HOST" "$@" 2>/dev/null || true
}

require_reachable_host() {
  if ! remote true >/dev/null 2>&1; then
    die "cannot reach $REMOTE_HOST over SSH.
  Check the host is up and your key is loaded (ssh-add -l), then retry.
  Override the target with REMOTE_HOST=user@host."
  fi
}

compose_remote() {
  local host_ip="${REMOTE_HOST#*@}"
  local orphans=""
  $REMOVE_ORPHANS && orphans="--remove-orphans"
  remote "cd $DEPLOY_DIR && LAUNCHER_CONTROL_PORT=8090 \
JUPYTER_PUBLIC_URL=http://${host_ip}:8008/lab \
$CONTAINER_ENGINE compose $COMPOSE_ARGS $* $orphans"
}

# compose_remote's read-only twin, for collecting diagnostics on a failure path
# where a second failure must not replace the message we are trying to print.
compose_probe() {
  remote_probe "cd $DEPLOY_DIR && $CONTAINER_ENGINE compose $COMPOSE_ARGS $*"
}

# ---------------------------------------------------------------------------
# Is this host serving Akida from the native `neurochip.service` unit rather
# than the containerized worker?
#
# It matters because both want port 8002, and the container can never win the
# argument usefully: workers/neurochip_hw/Dockerfile installs no Akida SDK, so
# it cannot serve real hardware routes at all. docker-compose.akida-native.yml
# exists for exactly this — it parks the worker in a `donotstart` profile and
# repoints suite_api/launcher-control at host.docker.internal:8002.
#
# Without this the run dies with:
#   failed to bind host port 0.0.0.0:8002/tcp: address already in use
# ---------------------------------------------------------------------------
resolve_akida_native() {
  if [ -n "$AKIDA_NATIVE" ]; then
    AKIDA_DETECTED_VIA="explicit override"
    return
  fi

  # systemd is the unambiguous signal, and `is-active` needs no root.
  local unit_state
  unit_state="$(remote_probe "systemctl is-active neurochip.service" | tr -d '\r')"
  if [ "$unit_state" = "active" ]; then
    AKIDA_NATIVE=1
    AKIDA_DETECTED_VIA="systemctl: neurochip.service is active"
    return
  fi
  if [ -n "$unit_state" ]; then
    AKIDA_NATIVE=0
    AKIDA_DETECTED_VIA="systemctl: neurochip.service is $unit_state"
    return
  fi

  # No systemd answer (unit absent, or systemctl unavailable). Fall back to:
  # something is serving 8002, and it is not one of our containers.
  local port_answers=false container_publishes=false
  if "$PYTHON3" - "http://${REMOTE_HOST#*@}:${NEUROCHIP_PORT}/health" <<'PY'
import sys, urllib.request
try:
    urllib.request.urlopen(sys.argv[1], timeout=4)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
  then port_answers=true; fi

  if [ -n "$(remote_probe "$CONTAINER_ENGINE ps --filter publish=$NEUROCHIP_PORT --format '{{.Names}}'")" ]; then
    container_publishes=true
  fi

  if $port_answers && ! $container_publishes; then
    AKIDA_NATIVE=1
    AKIDA_DETECTED_VIA="port $NEUROCHIP_PORT answers but no container publishes it"
  else
    AKIDA_NATIVE=0
    AKIDA_DETECTED_VIA="no native service found on port $NEUROCHIP_PORT"
  fi
}

apply_akida_overlay() {
  resolve_akida_native
  if [ "$AKIDA_NATIVE" = "1" ]; then
    COMPOSE_ARGS="$COMPOSE_ARGS -f docker-compose.akida-native.yml"
    log "Akida-native host ($AKIDA_DETECTED_VIA)"
    log "  → adding docker-compose.akida-native.yml: the containerized"
    log "    neurochip-hw-worker stays down (it has no Akida SDK) and port"
    log "    $NEUROCHIP_PORT is left to the native service."
    # The failed run that prompted this leaves a Created-but-unstarted
    # container behind. It can never work here, so clear it once.
    local stale
    stale="$(remote_probe "$CONTAINER_ENGINE ps -a --filter name=neurochip-hw-worker --format '{{.Names}}'" | tr -d '\r')"
    if [ -n "$stale" ]; then
      log "  → removing stale container(s): $(printf '%s' "$stale" | tr '\n' ' ')"
      $DRY_RUN || compose_remote "rm -sf neurochip-hw-worker" >/dev/null 2>&1 || true
    fi
  else
    log "Not an Akida-native host ($AKIDA_DETECTED_VIA)"
  fi
}

# ---------------------------------------------------------------------------
# Refuse to run into "address already in use". For each port the dev stack
# publishes, name whatever already holds it and decide whether it is ours.
# ---------------------------------------------------------------------------
STACK_PORTS=(9000 8090 8002 8003 8004 8006 8007 8008 8012)

check_port_conflicts() {
  log "Checking for port conflicts..."
  local blockers=() port holder
  for port in "${STACK_PORTS[@]}"; do
    # Our own containers are fine — `up` recreates them in place.
    holder="$(remote_probe "$CONTAINER_ENGINE ps --filter publish=$port --format '{{.Names}}'" | tr -d '\r')"
    if [ -n "$holder" ]; then
      continue
    fi
    # Port 8002 in native mode is meant to be taken — that is the whole point.
    if [ "$port" = "$NEUROCHIP_PORT" ] && [ "$AKIDA_NATIVE" = "1" ]; then
      continue
    fi
    # Bound by something that is not a container?
    if remote_probe "ss -ltn '( sport = :$port )'" | grep -q LISTEN; then
      local proc
      proc="$(remote_probe "ss -ltnp '( sport = :$port )'" | tail -n +2 | tr -d '\r')"
      blockers+=("$port|${proc:-<process name needs root>}")
    fi
  done

  [ ${#blockers[@]} -eq 0 ] && { log "  no conflicts"; return 0; }

  printf '\n' >&2
  warn "these stack ports are held by something that is not one of our containers:"
  local entry
  for entry in "${blockers[@]}"; do
    printf '    port %-6s %s\n' "${entry%%|*}" "${entry#*|}" >&2
  done
  if [ "${blockers[*]}" = "${blockers[*]#*<process name needs root>}" ]; then
    :
  else
    warn "  for process names run: ssh $REMOTE_HOST 'sudo ss -ltnp'"
  fi

  if ! $EVICT_PORTS; then
    die "refusing to start containers that would fail to bind.
  Rerun with ARGS='--evict-ports' to kill the holders, or free them yourself."
  fi

  for entry in "${blockers[@]}"; do
    port="${entry%%|*}"
    if [ "$port" = "$NEUROCHIP_PORT" ] && [ "$AKIDA_NATIVE" = "1" ]; then
      warn "  refusing to evict port $port — it belongs to the native"
      warn "  neurochip.service, and killing it is the opposite of the fix."
      continue
    fi
    log "  evicting port $port..."
    $DRY_RUN || remote "sudo fuser -k $port/tcp 2>/dev/null || true" || true
  done
}

# ---------------------------------------------------------------------------
# Map a changed repo path to the service work it implies.
#
# Prints zero or more "ACTION:service" lines. This table is the whole point of
# the script — the dev compose topology is deliberately uneven:
#
#   * suite_api is the ONLY service with a repo bind mount (`.:/repo`,
#     docker-compose.dev.yml:3-4) plus `--reload`, so anything it imports *by
#     path* goes live with no rebuild.
#   * The workers get `--reload` but NO bind mount, so their reloader watches
#     the code baked into the image — source edits need a rebuild.
#   * launcher-control bind-mounts three specific paths and its own comment says
#     they take effect "on container restart" — restart, not rebuild.
#   * neurocnl/neurocnl, Neurohub, Neurosense, Neurobench/neurobench are
#     pip-installed non-editable into the suite_api image
#     (suite_api/Dockerfile:30,35,42,50-51) — rebuild, even though the source
#     does get rsynced.
# ---------------------------------------------------------------------------
classify_path() {
  local path="$1"

  case "$path" in
    # Dockerfiles first: a Dockerfile change always outranks a source change.
    suite_api/Dockerfile)                    echo "REBUILD:suite_api"; return ;;
    Dockerfile.control)                      echo "REBUILD:launcher-control"; return ;;
    Dockerfile.lava)                         echo "REBUILD:lava-backend"; return ;;
    workers/neurosense_hw/Dockerfile)        echo "REBUILD:neurosense-hw-worker"; return ;;
    workers/neurobench_runner/Dockerfile)    echo "REBUILD:neurobench-runner-worker"; return ;;
    workers/neurochip_hw/Dockerfile)         echo "REBUILD:neurochip-hw-worker"; return ;;
    workers/neurocnl_physics/Dockerfile)     echo "REBUILD:neurocnl-physics-worker"; return ;;
    workers/snn_mlir_compiler/Dockerfile)    echo "REBUILD:snn-mlir-compiler"; return ;;
    workers/jupyter_server/Dockerfile)       echo "REBUILD:jupyter-server"; return ;;

    # Only these three are loaded by the dev stack, so only these justify a
    # recreate. prod/remote are bundled into the Flutter app by hash, so they
    # need the asset re-sync — but no dev container ever reads them.
    docker-compose.yml|docker-compose.dev.yml|docker-compose.akida-native.yml) \
                                             echo "RECREATE:all"; return ;;
    docker-compose.prod.yml|docker-compose.remote.yml) \
                                             echo "ASSETSYNC:-"; return ;;

    # Live via the suite_api bind mount — no container work at all.
    suite_api/*|neurocnl/backend/*)          echo "RELOAD:suite_api"; return ;;

    # Module frontends are Flutter packages compiled into the launcher app, not
    # backend code. Listed before the module-wide rebuild rules below so a Dart
    # edit can never trigger an image rebuild. (They are rsync-excluded too;
    # this is belt and braces.)
    */frontend/*)                            echo "NOOP:$path"; return ;;

    # pip-installed into the image; rsync moves the source but Python won't see it.
    neurocnl/neurocnl/*|neurocnl/pyproject.toml) echo "REBUILD:suite_api"; return ;;
    Neurohub/*|Neurosense/*)                 echo "REBUILD:suite_api"; return ;;
    Neurobench/neurobench/*)                 echo "REBUILD:suite_api"; return ;;

    # Bind-mounted into launcher-control; needs a restart to be picked up.
    nmtk/launcher_control/*|scripts/launcher_control_service.py) \
                                             echo "RESTART:launcher-control"; return ;;
    nmtk/neuro_toolkit/assets/*)             echo "RESTART:launcher-control"; return ;;

    # Per-worker source.
    workers/neurosense_hw/*)                 echo "REBUILD:neurosense-hw-worker"; return ;;
    workers/neurobench_runner/*)             echo "REBUILD:neurobench-runner-worker"; return ;;
    workers/neurochip_hw/*)                  echo "REBUILD:neurochip-hw-worker"; return ;;
    workers/neurocnl_physics/*)              echo "REBUILD:neurocnl-physics-worker"; return ;;
    workers/snn_mlir_compiler/*)             echo "REBUILD:snn-mlir-compiler"; return ;;
    workers/jupyter_server/*)                echo "REBUILD:jupyter-server"; return ;;

    *)                                       echo "NOOP:$path"; return ;;
  esac
}

# ---------------------------------------------------------------------------
# Containers in the compose project that no current compose file defines —
# leftovers from a monitoring stack whose compose file is gone (only
# monitoring/grafana/provisioning/… config remains in the repo). Compose warns
# about them on every run. Reported, never removed unless asked: they may hold
# data worth keeping.
report_orphans() {
  local orphans
  orphans="$(remote_probe "$CONTAINER_ENGINE ps -a \
--filter label=com.docker.compose.project=nmtk-deploy --format '{{.Names}}'" \
    | grep -Ei 'grafana|prometheus|alertmanager|loki|promtail' | tr -d '\r' | tr '\n' ' ' || true)"
  [ -z "${orphans// /}" ] && return 0
  log "Orphan containers present: ${orphans% }"
  log "  No compose file in the repo defines these any more. Compose will keep"
  log "  warning about them. Remove with ARGS='--remove-orphans' when you're"
  log "  sure you don't need their data."
}

explain() {
  local path verdict
  for path in "$@"; do
    printf '%-52s' "$path"
    local first=true
    while IFS= read -r verdict; do
      $first || printf '%-52s' ""
      first=false
      case "$verdict" in
        REBUILD:*)   printf 'rebuild %s (not bind-mounted)\n' "${verdict#REBUILD:}" ;;
        RESTART:*)   printf 'restart %s (bind-mounted)\n' "${verdict#RESTART:}" ;;
        RELOAD:*)    printf 'nothing — live via suite_api bind mount + --reload\n' ;;
        RECREATE:*)  printf 'recreate the stack\n' ;;
        ASSETSYNC:*) printf 'also: resync the Flutter asset bundle\n' ;;
        NOOP:*)      printf 'nothing — not a backend runtime path\n' ;;
      esac
    done < <(classify_path "$path")
  done
}

main() {
  if [ ${#EXPLAIN_PATHS[@]} -gt 0 ]; then
    explain "${EXPLAIN_PATHS[@]}"
    return 0
  fi

  log "Dev host: $REMOTE_HOST:$DEPLOY_DIR"
  $DRY_RUN && log "DRY RUN — nothing will be changed locally or on the host"

  require_reachable_host

  # Decide the compose file set before anything else uses compose_remote().
  apply_akida_overlay
  report_orphans

  # 1. Tests BEFORE the sync, so a failing change never reaches the dev host.
  if $SKIP_TESTS; then
    warn "skipping tests (--skip-tests)"
  else
    log "Running tests for changed modules (skip with --skip-tests)..."
    if $DRY_RUN; then
      log "  would run: scripts/run_ci_local.sh --changed"
    elif ! (cd "$REPO_ROOT" && ./scripts/run_ci_local.sh --changed); then
      die "tests failed — the dev host was left untouched. Fix, or rerun with --skip-tests."
    fi
  fi

  # 2. The app bundles its own copies of the compose files, pinned by hash. If
  #    they drifted, the app would deploy stale compose — and nothing in CI
  #    checks this, so check it here.
  if ! (cd "$REPO_ROOT" && "$PYTHON3" scripts/sync_flutter_deployment_assets.py --check >/dev/null 2>&1); then
    warn "Flutter deployment asset bundle is stale."
    warn "  run: python3 scripts/sync_flutter_deployment_assets.py   (then commit)"
  fi

  # 3. Sync, recording exactly what moved. --itemize-changes is what removes the
  #    need for any state tracking.
  local itemized
  if $DRY_RUN; then
    log "Computing what would sync..."
    # shellcheck disable=SC2086
    itemized="$(cd "$REPO_ROOT" && rsync -a --delete --dry-run --itemize-changes \
      -e "ssh $SSH_OPTS" --exclude-from="$EXCLUDE_FILE" . "$REMOTE_HOST:$DEPLOY_DIR/")"
  else
    log "Syncing source to $REMOTE_HOST..."
    remote "mkdir -p $DEPLOY_DIR"
    # shellcheck disable=SC2086
    itemized="$(cd "$REPO_ROOT" && rsync -a --delete --itemize-changes \
      -e "ssh $SSH_OPTS" --exclude-from="$EXCLUDE_FILE" . "$REMOTE_HOST:$DEPLOY_DIR/")"
  fi

  # Keep only transferred/changed *files*. rsync itemize codes: field 2 is the
  # entry type, so ">f" / "cf" are files sent; "*deleting" and directory-only
  # attribute lines are not source changes we need to act on.
  local changed_paths
  changed_paths="$(printf '%s\n' "$itemized" \
    | awk '$1 ~ /^[>c<][f]/ { $1=""; sub(/^ /,""); print }' || true)"

  # `--force-rebuild` promises "regardless of what changed", so it has to survive the
  # nothing-changed shortcut — otherwise the one case you reach for it in (the source is
  # already current but the running image is wrong) is exactly the case it ignores.
  if [ -z "$changed_paths" ] && [ ${#FORCED_SERVICES[@]} -eq 0 ]; then
    log "Backend source already current — nothing to sync, nothing to restart."
    $DRY_RUN || verify_health
    return 0
  fi
  if [ -z "$changed_paths" ]; then
    log "Backend source already current, but --force-rebuild was given."
  fi

  if [ -n "$changed_paths" ]; then
    local file_count
    file_count="$(printf '%s\n' "$changed_paths" | wc -l | tr -d ' ')"
    log "$file_count file(s) changed:"
    printf '%s\n' "$changed_paths" | sed 's/^/      /' | head -20
    [ "$file_count" -gt 20 ] && log "      … and $((file_count - 20)) more"
  fi

  # 4. Decide the minimum work.
  local rebuild=() restart=() reload=false recreate=false assetsync=false path verdict
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    while IFS= read -r verdict; do
      case "$verdict" in
        REBUILD:*)   rebuild+=("${verdict#REBUILD:}") ;;
        RESTART:*)   restart+=("${verdict#RESTART:}") ;;
        RELOAD:*)    reload=true ;;
        RECREATE:*)  recreate=true ;;
        ASSETSYNC:*) assetsync=true ;;
      esac
    done < <(classify_path "$path")
  done <<< "$changed_paths"

  for path in "${FORCED_SERVICES[@]+"${FORCED_SERVICES[@]}"}"; do
    rebuild+=("$path")
  done

  # Deduplicate.
  local uniq_rebuild=() uniq_restart=()
  if [ ${#rebuild[@]} -gt 0 ]; then
    while IFS= read -r path; do uniq_rebuild+=("$path"); done \
      < <(printf '%s\n' "${rebuild[@]}" | sort -u)
  fi
  if [ ${#restart[@]} -gt 0 ]; then
    while IFS= read -r path; do uniq_restart+=("$path"); done \
      < <(printf '%s\n' "${restart[@]}" | sort -u)
  fi

  # 5. Report the decision and why, then act.
  if $reload && [ ${#uniq_rebuild[@]} -eq 0 ] && [ ${#uniq_restart[@]} -eq 0 ] && ! $recreate; then
    log "Decision: no container work — those paths are bind-mounted into suite_api"
    log "          and uvicorn --reload picks them up."
  fi
  $assetsync && warn "compose files changed — rerun the asset sync and commit the bundle."

  # On an Akida-native host the containerized worker is profiled off entirely, so
  # rebuilding it achieves nothing — the running service is the native one.
  if [ "$AKIDA_NATIVE" = "1" ] && [ ${#uniq_rebuild[@]} -gt 0 ]; then
    local kept=()
    for path in "${uniq_rebuild[@]}"; do
      if [ "$path" = "neurochip-hw-worker" ]; then
        log "Skipping rebuild of neurochip-hw-worker: this host serves Akida from"
        log "  the native service, so the container stays down either way."
      else
        kept+=("$path")
      fi
    done
    uniq_rebuild=("${kept[@]+"${kept[@]}"}")
  fi

  # Anything below starts containers, so establish now that their ports are free
  # rather than discovering it half way through a recreate.
  if $recreate || [ ${#uniq_rebuild[@]} -gt 0 ]; then
    check_port_conflicts
  fi

  if $recreate; then
    log "Decision: recreate the stack (compose files changed)."
    $DRY_RUN || compose_remote "up -d"
  fi

  if [ ${#uniq_rebuild[@]} -gt 0 ]; then
    if $NO_REBUILD; then
      warn "rebuild needed for: ${uniq_rebuild[*]} — skipped (--no-rebuild)."
      warn "  those changes are NOT live on the host."
    else
      log "Decision: rebuild ${uniq_rebuild[*]}"
      log "          (not bind-mounted — the running image holds the old code)."
      $DRY_RUN || compose_remote "up -d --build ${uniq_rebuild[*]}"
    fi
  fi

  if [ ${#uniq_restart[@]} -gt 0 ]; then
    log "Decision: restart ${uniq_restart[*]} (bind-mounted, applied on restart)."
    $DRY_RUN || compose_remote "restart ${uniq_restart[*]}"
  fi

  if $DRY_RUN; then
    log "DRY RUN complete — nothing was changed."
    return 0
  fi

  verify_health
  log "Dev backend updated."
}

verify_health() {
  local host_ip="${REMOTE_HOST#*@}"
  local url="http://${host_ip}:9000/api/suite/health"
  # Poll rather than probe once. A freshly rebuilt suite_api image imports torch, akida,
  # brian2 and samna and then runs Alembic before it binds, which is well over the 10s a
  # single attempt used to allow — and the run that recreates the container is exactly the
  # run that probes it first. Same 90s/2s cadence as wait_for_control_api() in
  # scripts/dev/lib.sh; a separate loop because this one needs the JSON body, not just a 200.
  local timeout_secs=90 start version=""
  start=$(date +%s)
  log "Verifying backend health (timeout ${timeout_secs}s)..."
  while true; do
    version="$("$PYTHON3" - "$url" <<'PY'
import json, sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1], timeout=2) as r:
        print(json.loads(r.read()).get("version", "unknown"))
except Exception:
    print("")
PY
)"
    [ -n "$version" ] && break
    if [ "$(( $(date +%s) - start ))" -ge "$timeout_secs" ]; then
      die "Suite API did not answer at $url within ${timeout_secs}s.
  An empty reply (rather than a refused connection) means the container is up but uvicorn
  died — read the traceback:
    ssh $REMOTE_HOST '$CONTAINER_ENGINE logs --tail 50 nmtk-deploy-suite_api-1'"
    fi
    sleep 2
  done
  log "  Suite API ok (version: $version)"
  wait_for_control_api "http://${host_ip}:8090"
  check_jupyter_health "$host_ip"
}

check_jupyter_health() {
  # jupyter-server is unprofiled, so a stack-wide `up -d` starts it — but the
  # targeted `up -d --build <svc>` / `restart <svc>` branches don't, and it has no
  # bind mount in docker-compose.dev.yml. So a stopped or crash-looping container
  # survives any number of dev-updates, and the first symptom is a 503 out of
  # neurocnl/backend/app/routers/notebook.py hours later, in the CNL Studio
  # notebook step. Gate on it here instead.
  local host_ip="$1"
  if $SKIP_JUPYTER_CHECK; then
    warn "skipping Jupyter check (--skip-jupyter-check)"
    return 0
  fi
  local url="http://${host_ip}:8008/api/status"
  # 150s, not the 90s the two checks above use: compose gives this service
  # start_period: 120s (docker-compose.yml) because the image imports torch,
  # tensorflow, jax and every SNN framework before it binds.
  local timeout_secs=150 start
  start=$(date +%s)
  log "Verifying Jupyter health (timeout ${timeout_secs}s)..."
  while true; do
    if "$PYTHON3" - "$url" 2>/dev/null <<'PY'
import sys, urllib.request
try:
    urllib.request.urlopen(sys.argv[1], timeout=2)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then
      log "  Jupyter ok"
      return 0
    fi
    if [ "$(( $(date +%s) - start ))" -ge "$timeout_secs" ]; then
      report_jupyter_failure "$url" "$timeout_secs"
    fi
    sleep 2
  done
}

# Print WHY, not just THAT. An error that says "go run these two ssh commands"
# just makes the reader do the round-trip by hand, so collect the container
# state and the tail of the logs and put them in the failure itself.
report_jupyter_failure() {
  local url="$1" timeout_secs="$2" state logs hint
  state="$(compose_probe ps -a jupyter-server)"
  logs="$(compose_probe logs --tail 40 --no-color jupyter-server)"

  if [ -z "$state" ]; then
    # Both probes go over the same multiplexed SSH connection the sync already
    # used, so an empty answer here is the container missing, not SSH breaking.
    state="(no jupyter-server container — never created, or the image build failed)"
    hint="The service does not exist on the host. Build it:
    make dev-update ARGS='--force-rebuild jupyter-server'
  Expect a long build: the image installs torch, tensorflow, jax and every SNN framework."
  elif printf '%s' "$state" | grep -qi 'restarting'; then
    hint="The container is crash-looping — the traceback is in the log tail above."
  elif printf '%s' "$state" | grep -qi 'exit'; then
    hint="The container exited — the reason is in the log tail above."
  elif printf '%s' "$state" | grep -qi 'health: starting'; then
    hint="Still inside its start_period. It may simply need longer than ${timeout_secs}s on this host; rerun."
  else
    hint="The container looks up but is not serving on 8008. Restart it:
    ssh $REMOTE_HOST 'cd $DEPLOY_DIR && $CONTAINER_ENGINE compose $COMPOSE_ARGS restart jupyter-server'"
  fi

  printf '\n--- jupyter-server container state ---\n%s\n' "$state" >&2
  printf '\n--- jupyter-server logs (last 40 lines) ---\n%s\n\n' \
    "${logs:-(no logs — the container produced no output)}" >&2

  die "Jupyter did not answer at $url within ${timeout_secs}s.
  CNL Studio's notebook step will 503 until this is up.
  $hint
  Bypass this gate with --skip-jupyter-check."
}

main "$@"
