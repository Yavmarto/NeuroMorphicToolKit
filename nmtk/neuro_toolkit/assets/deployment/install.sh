#!/usr/bin/env bash
set -euo pipefail

ENGINE="${1:-docker}"
BACKEND_PORT="${2:-9000}"
IMAGE_TAG="${3:-latest}"
CLEAN_INSTALL="${4:-false}"
PUBLIC_HOST="${5:-127.0.0.1}"
STATUS_FILE="${6:-deployment.status}"
LOG_FILE="${7:-deployment.log}"

CURRENT_STAGE=""

# Every step that talks to a container registry or to the container runtime gets
# an upper bound. Without one, a stalled pull or a wedged runtime leaves the app
# sitting on the same percentage forever with nothing to report.
DOWN_TIMEOUT="${NMTK_DEPLOY_DOWN_TIMEOUT:-300}"
PULL_TIMEOUT="${NMTK_DEPLOY_PULL_TIMEOUT:-1200}"
# A download of this size can be damaged in transit by a flaky link. Retrying is
# the whole remedy, and the end user has no terminal to do it by hand.
PULL_ATTEMPTS="${NMTK_DEPLOY_PULL_ATTEMPTS:-3}"
PULL_RETRY_DELAY="${NMTK_DEPLOY_PULL_RETRY_DELAY:-5}"
UP_TIMEOUT="${NMTK_DEPLOY_UP_TIMEOUT:-600}"
DIAGNOSTICS_TIMEOUT="${NMTK_DEPLOY_DIAGNOSTICS_TIMEOUT:-60}"

write_status() {
  CURRENT_STAGE="$1"
  printf '%s|%s|%s\n' "$1" "$2" "$3" >"$STATUS_FILE"
  printf '[nmtk-deploy] %s\n' "$3" >>"$LOG_FILE"
}

capture_failure_diagnostics() {
  printf '%s\n' '[nmtk-deploy] Capturing container diagnostics.' >>"$LOG_FILE"
  printf '%s\n' '[nmtk-deploy] Container state:' >>"$LOG_FILE"
  compose_with_timeout "$DIAGNOSTICS_TIMEOUT" ps -a >>"$LOG_FILE" 2>&1 || true
  printf '%s\n' '[nmtk-deploy] Suite API and launcher-control logs:' >>"$LOG_FILE"
  compose_with_timeout "$DIAGNOSTICS_TIMEOUT" \
    logs --tail 200 suite_api launcher-control >>"$LOG_FILE" 2>&1 || true
}

# Reports a stage failure the app can act on, instead of leaving the status file
# on a percentage that will never change.
fail_stage() {
  capture_failure_diagnostics
  write_status failed 100 "$1"
  exit 1
}

handle_failure() {
  capture_failure_diagnostics
  case "$CURRENT_STAGE" in
    verifying_suite_api)
      write_status failed 100 "Suite API did not become ready; diagnostics captured."
      ;;
    verifying_launcher_control)
      write_status failed 100 "Launcher control did not become ready; diagnostics captured."
      ;;
    *)
      write_status failed 100 "Deployment failed; diagnostics captured."
      ;;
  esac
}

COMPOSE_FILES=(
  -f docker-compose.yml
  -f docker-compose.prod.yml
  -f docker-compose.remote.yml
)

compose() {
  "$ENGINE" compose --project-name nmtk "${COMPOSE_FILES[@]}" "$@"
}

compose_with_timeout() {
  local seconds="$1"
  shift
  timeout --signal=TERM --kill-after=30s "${seconds}s" \
    "$ENGINE" compose --project-name nmtk "${COMPOSE_FILES[@]}" "$@"
}

cleanup_runtime() {
  local runtime="$1"
  local project ids volumes known_ids
  command -v "$runtime" >/dev/null 2>&1 || return 0
  "$runtime" info >>"$LOG_FILE" 2>&1 || {
    printf '[nmtk-deploy] Existing %s installation is not accessible; cleanup cannot be verified.\n' \
      "$runtime" >>"$LOG_FILE"
    return 1
  }
  known_ids="$(
    "$runtime" ps -a --format '{{.ID}} {{.Names}}' 2>>"$LOG_FILE" |
      awk '$2 ~ /^(nmtk|nmtk-deploy|deploy)[_-](suite_api|neurosense-hw-worker|neurobench-runner-worker|neurochip-hw-worker|lava-backend|launcher-control|neurocnl-physics-worker|snn-mlir-compiler|jupyter-server)([-_][0-9]+)?$/ {print $1}'
  )"
  if [ -n "$known_ids" ]; then
    printf '[nmtk-deploy] Removing known stale %s NMTK containers.\n' \
      "$runtime" >>"$LOG_FILE"
    # Container IDs contain no whitespace, and both CLIs accept multiple IDs.
    # shellcheck disable=SC2086
    "$runtime" rm -f $known_ids >>"$LOG_FILE" 2>&1
  fi
  for project in nmtk nmtk-deploy deploy; do
    ids="$(
      {
        "$runtime" ps -aq \
          --filter "label=com.docker.compose.project=$project"
        "$runtime" ps -aq \
          --filter "label=io.podman.compose.project=$project"
      } 2>>"$LOG_FILE" | awk 'NF' | sort -u
    )"
    if [ -n "$ids" ]; then
      printf '[nmtk-deploy] Removing stale %s containers for project %s.\n' \
        "$runtime" "$project" >>"$LOG_FILE"
      # Container IDs contain no whitespace, and both CLIs accept multiple IDs.
      # shellcheck disable=SC2086
      "$runtime" rm -f $ids >>"$LOG_FILE" 2>&1
    fi
    if [ "$CLEAN_INSTALL" = "true" ]; then
      volumes="$(
        {
          "$runtime" volume ls -q \
            --filter "label=com.docker.compose.project=$project"
          "$runtime" volume ls -q \
            --filter "label=io.podman.compose.project=$project"
        } 2>>"$LOG_FILE" | awk 'NF' | sort -u
      )"
      if [ -n "$volumes" ]; then
        printf '[nmtk-deploy] Factory reset removing %s volumes for project %s.\n' \
          "$runtime" "$project" >>"$LOG_FILE"
        # shellcheck disable=SC2086
        "$runtime" volume rm -f $volumes >>"$LOG_FILE" 2>&1
      fi
    fi
  done
}

trap handle_failure ERR

mkdir -p credentials
if [ ! -s credentials/admin-token ]; then
  umask 077
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32 >credentials/admin-token
  else
    head -c 48 /dev/urandom | base64 | tr -d '\n=' >credentials/admin-token
  fi
fi
chmod 600 credentials/admin-token

export SUITE_API_PORT="$BACKEND_PORT"
export LAUNCHER_CONTROL_PORT=8090
export NMTK_IMAGE_TAG="$IMAGE_TAG"
export JUPYTER_PUBLIC_URL="http://$PUBLIC_HOST:8008/lab"
if [ "$ENGINE" = "podman" ]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
fi

write_status preflight_running 10 "Validating container provider"
"$ENGINE" info >>"$LOG_FILE" 2>&1
compose config --quiet >>"$LOG_FILE" 2>&1

write_status reconciling_existing_install 16 "Removing existing NMTK containers"
MIGRATION_DIR=".migration-staging/p0-owner-v1"
MIGRATION_MARKER=".migration-staging/p0-owner-v1.complete"
if [ "$CLEAN_INSTALL" != "true" ] && [ ! -f "$MIGRATION_MARKER" ]; then
  mkdir -p "$MIGRATION_DIR"
  compose cp suite_api:/repo/projects.db "$MIGRATION_DIR/neurosim-projects.db" \
    >>"$LOG_FILE" 2>&1 || true
  compose cp suite_api:/repo/Neurochip/neurochip/app/deployments.db \
    "$MIGRATION_DIR/neurochip-deployments.db" >>"$LOG_FILE" 2>&1 || true
  compose cp suite_api:/home/app/data/neurobench.sqlite \
    "$MIGRATION_DIR/neurobench.sqlite" >>"$LOG_FILE" 2>&1 || true
  compose cp neurochip-hw-worker:/tmp/akida-models \
    "$MIGRATION_DIR/akida-models" >>"$LOG_FILE" 2>&1 || true
  compose cp neurosense-hw-worker:/repo/recordings \
    "$MIGRATION_DIR/neurosense-recordings" >>"$LOG_FILE" 2>&1 || true
fi
cleanup_runtime docker
cleanup_runtime podman

if [ "$CLEAN_INSTALL" = "true" ]; then
  write_status installing_prerequisites 20 "Factory resetting NMTK server data"
  DOWN_ARGS=(down -v --remove-orphans)
else
  write_status installing_prerequisites 20 "Preserving NMTK server data"
  DOWN_ARGS=(down --remove-orphans)
fi
# A nonzero exit is tolerated here — there may be nothing to stop yet — but a
# timeout is not: it means the container runtime itself stopped answering.
set +e
compose_with_timeout "$DOWN_TIMEOUT" "${DOWN_ARGS[@]}" >>"$LOG_FILE" 2>&1
down_exit="$?"
set -e
if [ "$down_exit" -eq 124 ]; then
  fail_stage "Stopping the existing NMTK containers timed out after ${DOWN_TIMEOUT}s. The container runtime on the server stopped responding; restart the server, then retry setup."
fi

write_status pulling_images 45 "Pulling backend images"
pull_started="$SECONDS"
pull_attempt=1
while :; do
  compose_with_timeout "$PULL_TIMEOUT" pull >>"$LOG_FILE" 2>&1 &
  pull_pid="$!"
  # Republish the stage every few seconds while the pull runs. The images are
  # large and this is by far the longest step, so the app has to be able to tell
  # "slow but alive" from "dead".
  while kill -0 "$pull_pid" 2>/dev/null; do
    sleep 5
    if kill -0 "$pull_pid" 2>/dev/null; then
      write_status pulling_images 45 \
        "Pulling backend images ($((SECONDS - pull_started))s elapsed)"
    fi
  done
  set +e
  wait "$pull_pid"
  pull_exit="$?"
  set -e
  [ "$pull_exit" -eq 0 ] && break
  if [ "$pull_exit" -eq 124 ]; then
    # Repeating a pull that already spent the whole budget would only spend it
    # again, so a timeout is reported rather than retried.
    fail_stage "Downloading the backend images timed out after ${PULL_TIMEOUT}s. Check that the server can reach ghcr.io, then retry setup."
  fi
  if [ "$pull_attempt" -ge "$PULL_ATTEMPTS" ]; then
    fail_stage "The backend images could not be downloaded after ${PULL_ATTEMPTS} attempts; diagnostics were captured in the deployment log."
  fi
  # Image layers occasionally arrive damaged over a long download ("crc32
  # mismatch"). Nothing bad is kept on disk, and layers that already arrived are
  # reused, so fetching again costs only the damaged image.
  printf '[nmtk-deploy] Image download attempt %s of %s failed; retrying.\n' \
    "$pull_attempt" "$PULL_ATTEMPTS" >>"$LOG_FILE"
  pull_attempt=$((pull_attempt + 1))
  write_status pulling_images 45 \
    "Retrying the backend image download (attempt $pull_attempt of $PULL_ATTEMPTS)"
  sleep "$PULL_RETRY_DELAY"
done

write_status starting_containers 70 "Preparing launcher workspace storage"
# Older remote deployments ran launcher-control as root and could leave this
# named volume root-owned. The image itself runs as appuser, so normalize the
# persistent paths before starting the normal unprivileged service. This keeps
# UI-only workspace preferences writable across reloads without asking the
# end user to repair container permissions manually.
if ! compose run --rm --no-deps --user 0:0 \
  --cap-add CHOWN \
  --entrypoint sh launcher-control \
  -c 'mkdir -p /app/state /app/data && chown -R appuser:appuser /app/state /app/data' \
  >>"$LOG_FILE" 2>&1; then
  printf '%s\n' \
    '[nmtk-deploy] Workspace preference storage could not be migrated; continuing because backend deployment is unaffected.' \
    >>"$LOG_FILE"
fi

write_status starting_containers 80 "Starting backend containers"
if ! bash ./nmtk-stack.sh install "$ENGINE" >>"$LOG_FILE" 2>&1; then
  fail_stage "The NMTK backend could not be registered to start automatically after a server reboot."
fi
set +e
timeout --signal=TERM --kill-after=30s "${UP_TIMEOUT}s" \
  bash ./nmtk-stack.sh start "$ENGINE" >>"$LOG_FILE" 2>&1
up_exit="$?"
set -e
if [ "$up_exit" -eq 124 ]; then
  fail_stage "Starting the backend containers timed out after ${UP_TIMEOUT}s. Diagnostics were captured in the deployment log; retry setup."
elif [ "$up_exit" -ne 0 ]; then
  fail_stage "The backend containers could not be started; diagnostics were captured in the deployment log."
fi

write_status verifying_suite_api 90 "Waiting for Suite API"
for _attempt in $(seq 1 60); do
  if curl --silent --show-error --fail \
    "http://127.0.0.1:$BACKEND_PORT/api/suite/health" \
    >>"$LOG_FILE" 2>&1; then
    break
  fi
  sleep 2
done
curl --silent --show-error --fail \
  "http://127.0.0.1:$BACKEND_PORT/api/suite/health" \
  >>"$LOG_FILE" 2>&1

if [ -d "$MIGRATION_DIR" ] && [ ! -f "$MIGRATION_MARKER" ]; then
  write_status verifying_suite_api 93 "Migrating saved backend data"
  migration_ok=true
  migrate_sqlite() {
    local service="$1" source="$2" target="$3" remote_source
    [ -f "$source" ] || return 0
    remote_source="/tmp/nmtk-legacy-$(basename "$source")"
    compose cp migrate_legacy.py "$service:/tmp/nmtk-migrate-legacy.py" \
      >>"$LOG_FILE" 2>&1 && \
      compose cp "$source" "$service:$remote_source" >>"$LOG_FILE" 2>&1 && \
      compose exec -T "$service" python /tmp/nmtk-migrate-legacy.py \
        "$remote_source" "$target" >>"$LOG_FILE" 2>&1 || migration_ok=false
  }
  migrate_directory() {
    local service="$1" source="$2" target="$3" remote_source
    [ -d "$source" ] || return 0
    remote_source="/tmp/nmtk-legacy-$(basename "$source")"
    compose cp "$source" "$service:$remote_source" >>"$LOG_FILE" 2>&1 && \
      compose exec -T --user 0:0 "$service" sh -c \
        "mkdir -p '$target' && cp -Rn '$remote_source'/.' '$target'/" \
        >>"$LOG_FILE" 2>&1 || migration_ok=false
  }
  migrate_sqlite suite_api "$MIGRATION_DIR/neurosim-projects.db" \
    /home/app/data/neurosim/projects.db
  migrate_sqlite suite_api "$MIGRATION_DIR/neurochip-deployments.db" \
    /home/app/data/neurochip/deployments.db
  migrate_sqlite neurobench-runner-worker "$MIGRATION_DIR/neurobench.sqlite" \
    /app/data/neurobench.sqlite
  migrate_directory neurochip-hw-worker "$MIGRATION_DIR/akida-models" \
    /app/data/akida-models
  migrate_directory neurosense-hw-worker "$MIGRATION_DIR/neurosense-recordings" \
    /app/recordings
  if [ "$migration_ok" != "true" ]; then
    fail_stage "Saved backend data could not be migrated safely; the protected staging copy was preserved."
  fi
fi

write_status verifying_launcher_control 96 "Waiting for launcher control"
for _attempt in $(seq 1 60); do
  if curl --silent --show-error --fail \
    "http://127.0.0.1:8090/health" >>"$LOG_FILE" 2>&1; then
    break
  fi
  sleep 2
done
curl --silent --show-error --fail \
  "http://127.0.0.1:8090/health" >>"$LOG_FILE" 2>&1

write_status verifying_optional_capabilities 98 "Checking optional capabilities"
if ! curl --silent --show-error --fail \
  "http://127.0.0.1:8008/api/status" >>"$LOG_FILE" 2>&1; then
  printf '%s\n' \
    "degraded optional capability: Jupyter is not ready; core services are available." \
    >>"$LOG_FILE"
fi

if [ -d "$MIGRATION_DIR" ] && [ ! -f "$MIGRATION_MARKER" ]; then
  touch "$MIGRATION_MARKER"
  rm -rf "$MIGRATION_DIR"
fi

write_status completed 100 "Backend and launcher control are ready"
