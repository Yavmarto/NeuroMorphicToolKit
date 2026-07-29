#!/usr/bin/env bash
# dev_update.sh — daily driver: push local backend source to the dev host and do
# the minimum needed to make it live.
#
# Usage: scripts/dev_update.sh [OPTIONS]
#   --skip-tests           don't run the changed-module test suites first
#   --no-rebuild           sync only; warn instead of rebuilding
#   --force-rebuild SVC    rebuild SVC regardless of what changed (repeatable)
#   --dry-run              decide and print; change nothing, locally or remotely
#   --explain PATH...      print what each path would trigger, and exit. Needs no
#                          host — use it to check the table or ask "why did it
#                          rebuild that?"
#   -h | --help
#
# Env: REMOTE_HOST (default moosebuntu@192.168.2.51), DEPLOY_DIR, CONTAINER_ENGINE
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
NO_REBUILD=false
DRY_RUN=false
FORCED_SERVICES=()
EXPLAIN_PATHS=()

PYTHON3="$(find_python3)" || { echo "error: no python3 found" >&2; exit 1; }

log()  { printf '==> %s\n' "$*"; }
warn() { printf '==> WARNING: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-tests)    SKIP_TESTS=true ;;
    --no-rebuild)    NO_REBUILD=true ;;
    --force-rebuild) shift; [ $# -gt 0 ] || die "--force-rebuild needs a service name"
                     FORCED_SERVICES+=("$1") ;;
    --dry-run)       DRY_RUN=true ;;
    --explain)       shift; [ $# -gt 0 ] || die "--explain needs at least one path"
                     EXPLAIN_PATHS=("$@"); break ;;
    -h|--help)       sed -n '2,20p' "$0"; exit 0 ;;
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

compose_remote() {
  local host_ip="${REMOTE_HOST#*@}"
  remote "cd $DEPLOY_DIR && LAUNCHER_CONTROL_PORT=8090 \
JUPYTER_PUBLIC_URL=http://${host_ip}:8008/lab \
$CONTAINER_ENGINE compose $COMPOSE_ARGS $*"
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

    # Compose changed: recreate everything affected, and the app's asset bundle
    # pins these by hash, so it needs re-syncing too.
    docker-compose*.yml)                     echo "RECREATE:all"; echo "ASSETSYNC:-"; return ;;

    # Live via the suite_api bind mount — no container work at all.
    suite_api/*|neurocnl/backend/*)          echo "RELOAD:suite_api"; return ;;

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

  if [ -z "$changed_paths" ]; then
    log "Backend source already current — nothing to sync, nothing to restart."
    $DRY_RUN || verify_health
    return 0
  fi

  local file_count
  file_count="$(printf '%s\n' "$changed_paths" | wc -l | tr -d ' ')"
  log "$file_count file(s) changed:"
  printf '%s\n' "$changed_paths" | sed 's/^/      /' | head -20
  [ "$file_count" -gt 20 ] && log "      … and $((file_count - 20)) more"

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
  log "Verifying backend health..."
  local version
  version="$("$PYTHON3" - "http://${host_ip}:9000/api/suite/health" <<'PY'
import json, sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1], timeout=10) as r:
        print(json.loads(r.read()).get("version", "unknown"))
except Exception:
    print("")
PY
)"
  if [ -z "$version" ]; then
    die "Suite API did not answer at http://${host_ip}:9000/api/suite/health"
  fi
  log "  Suite API ok (version: $version)"
  wait_for_control_api "http://${host_ip}:8090"
}

main "$@"
