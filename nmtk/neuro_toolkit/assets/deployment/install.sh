#!/usr/bin/env bash
set -euo pipefail

ENGINE="${1:-docker}"
BACKEND_PORT="${2:-9000}"
IMAGE_TAG="${3:-latest}"
CLEAN_INSTALL="${4:-false}"
PUBLIC_HOST="${5:-127.0.0.1}"
STATUS_FILE="${6:-deployment.status}"
LOG_FILE="${7:-deployment.log}"
shift "$(($# < 7 ? $# : 7))"

# Optional, additive to the positional args above: mints an app-credential
# login (see launcher_auth.py) alongside the existing admin-token mechanism.
# Neither flag is required -- an already-provisioned host with no flags
# passed just leaves credentials/app/users.json untouched.
APP_USERNAME=""
APP_PASSWORD=""

# Rollback policy and schema-migration handling.
#
# auto_rollback (the default) restores the last-good images when an update
# fails its health verification. It is deliberately disabled for any release
# that moves data: rolling application code back over a schema that has
# already migrated corrupts state. "auto" treats the legacy data-migration
# step below as the signal; a release that migrates schema inside its own
# images must be flagged explicitly with --schema-migration.
ROLLBACK_POLICY="${NMTK_ROLLBACK_POLICY:-auto}"
SCHEMA_MIGRATION="${NMTK_SCHEMA_MIGRATION:-auto}"
while [ $# -gt 0 ]; do
  case "$1" in
    --app-username)
      APP_USERNAME="${2:-}"
      shift 2
      ;;
    --app-password)
      APP_PASSWORD="${2:-}"
      shift 2
      ;;
    --rollback-policy)
      ROLLBACK_POLICY="${2:-auto}"
      shift 2
      ;;
    --schema-migration)
      SCHEMA_MIGRATION="${2:-auto}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

CURRENT_STAGE=""
MIGRATION_RAN=false
PINNED_VERSION=""
ROLLED_BACK_VERSION=""

# Where the installer remembers what was running before an update. The
# record is line-oriented so it needs no JSON parser on the host:
#   tag|<pinned tag>
#   version|<release version>
#   captured|<iso timestamp>
#   image|<image ref>|<image id>|<repo digest>
STATE_DIR="${NMTK_STATE_DIR:-.nmtk-state}"
LAST_GOOD_STATE="$STATE_DIR/last-good.state"
PENDING_STATE="$STATE_DIR/pending-update.state"
# A local-only alias applied to every restored image, so a rollback does not
# depend on the mutable tag or on a release still being published.
ROLLBACK_TAG="nmtk-lastgood"
SUITE_API_IMAGE="ghcr.io/completed-spoon-6/neuromorphictoolkit/suite-api"

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
# Health verification polls. Kept configurable so the rollback path can be
# exercised without spending the full two-minute budget twice.
HEALTH_ATTEMPTS="${NMTK_DEPLOY_HEALTH_ATTEMPTS:-60}"
HEALTH_INTERVAL="${NMTK_DEPLOY_HEALTH_INTERVAL:-2}"

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

# ---------------------------------------------------------------------------
# Failure handling and rollback.

# Only a failure after the old stack was already stopped can be repaired by
# restoring it. Earlier failures leave whatever was running untouched.
rollback_eligible_stage() {
  case "$CURRENT_STAGE" in
    pulling_images | starting_containers | verifying_suite_api | \
      verifying_launcher_control | verifying_optional_capabilities | \
      updating_akida_runtime)
      return 0
      ;;
  esac
  return 1
}

# The CTO-approved rule: automatic rollback only when the release carries no
# schema or data migration. A migrated database must never be reverted silently
# to code that predates it.
auto_rollback_allowed() {
  [ "$ROLLBACK_POLICY" = "auto" ] || return 1
  rollback_eligible_stage || return 1
  case "$SCHEMA_MIGRATION" in
    true) return 1 ;;
    false) return 0 ;;
    *) [ "$MIGRATION_RAN" = "true" ] && return 1 || return 0 ;;
  esac
}

health_probe() {
  local url="$1" attempt
  for ((attempt = 1; attempt <= HEALTH_ATTEMPTS; attempt++)); do
    if curl --silent --show-error --fail "$url" >>"$LOG_FILE" 2>&1; then
      return 0
    fi
    sleep "$HEALTH_INTERVAL"
  done
  return 1
}

# Puts the exact pre-update images back and re-verifies. Returns non-zero if
# any step fails, so the caller can report that recovery itself failed.
rollback_to_last_good() {
  local failure_reason="$1" source prev_version prev_tag
  source="$PENDING_STATE"
  state_has_images "$source" || source="$LAST_GOOD_STATE"
  if ! state_has_images "$source"; then
    printf '%s\n' \
      '[nmtk-deploy] No pre-update image snapshot exists; automatic rollback is not possible.' \
      >>"$LOG_FILE"
    return 1
  fi
  prev_version="$(state_value "$source" version)"
  prev_tag="$(state_value "$source" tag)"
  [ -n "$prev_tag" ] || prev_tag="latest"
  write_status rolling_back 99 \
    "Restoring ${prev_version:-$prev_tag} after ${failure_reason}"
  printf '[nmtk-deploy] Rolling back to %s (tag %s).\n' \
    "${prev_version:-unknown}" "$prev_tag" >>"$LOG_FILE"
  set +e
  compose_with_timeout "$DOWN_TIMEOUT" down --remove-orphans >>"$LOG_FILE" 2>&1
  if ! restore_images_from_state "$source"; then
    printf '%s\n' \
      '[nmtk-deploy] Rollback could not restore the previous images.' >>"$LOG_FILE"
    set -e
    return 1
  fi
  export NMTK_IMAGE_TAG="$ROLLBACK_TAG"
  if ! bash ./nmtk-stack.sh start "$ENGINE" >>"$LOG_FILE" 2>&1; then
    printf '%s\n' \
      '[nmtk-deploy] Rollback images were restored but the stack did not start.' \
      >>"$LOG_FILE"
    set -e
    return 1
  fi
  if health_probe "http://127.0.0.1:$BACKEND_PORT/api/suite/health" &&
    health_probe "http://127.0.0.1:8090/health"; then
    ROLLED_BACK_VERSION="${prev_version:-$prev_tag}"
    printf '[nmtk-deploy] Rollback to %s verified.\n' \
      "$ROLLED_BACK_VERSION" >>"$LOG_FILE"
    set -e
    return 0
  fi
  printf '%s\n' \
    '[nmtk-deploy] Rollback started but the restored stack did not become healthy.' \
    >>"$LOG_FILE"
  set -e
  return 1
}

# Single exit path for both explicit stage failures and the ERR trap. It
# attempts the approved rollback, then writes a status that names the release
# that failed and, when one ran, the release it was rolled back to.
report_failure() {
  local message="$1" failed_version source
  failed_version="${PINNED_VERSION:-$IMAGE_TAG}"
  source="$PENDING_STATE"
  state_has_images "$source" || source="$LAST_GOOD_STATE"
  if auto_rollback_allowed &&
    rollback_to_last_good "release ${failed_version} failed"; then
    write_status failed 100 \
      "Release ${failed_version} failed health verification; rolled back to ${ROLLED_BACK_VERSION}. The backend is running the previous release."
    exit 1
  fi
  # A rollback was available but was withheld because the release moves data.
  # Say so explicitly rather than reporting a bare failure.
  if state_has_images "$source" && rollback_eligible_stage &&
    { [ "$SCHEMA_MIGRATION" = "true" ] || [ "$MIGRATION_RAN" = "true" ]; }; then
    write_status failed 100 \
      "${message} Release ${failed_version} includes a schema or data migration, so it was not rolled back automatically. Restore the previous release by hand or ship a fixed release."
    exit 1
  fi
  write_status failed 100 "$message"
  exit 1
}

# Reports a stage failure the app can act on, instead of leaving the status file
# on a percentage that will never change.
fail_stage() {
  capture_failure_diagnostics
  report_failure "$1"
}

# Catch-all for an unexpected command failure. It deliberately does not exit
# or roll back: the ERR trap also fires on commands whose non-zero status the
# script tolerates (the pull retry waits on a background job), and bailing out
# there would abort a retry that is about to succeed. Every failure the deploy
# actually acts on goes through fail_stage, which does roll back.
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

state_value() {
  local file="$1" key="$2"
  [ -s "$file" ] || return 0
  awk -F'|' -v key="$key" '$1 == key { print $2; exit }' "$file" 2>/dev/null || true
}

# A snapshot with no images is not a usable rollback target (a first install,
# or one where nothing was running).
state_has_images() {
  [ -s "${1:-}" ] || return 1
  grep -q '^image|' "$1" 2>/dev/null
}

# Snapshots the image reference, image ID and repo digest of every running
# container, so a later rollback can restore those exact bits. The old stack is
# force-removed during reconciliation, so this has to run before that.
capture_running_state() {
  local file="$1" tag="$2" version="$3" ids
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  {
    printf 'tag|%s\n' "$tag"
    printf 'version|%s\n' "$version"
    printf 'captured|%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$file.tmp" 2>/dev/null || return 0
  set +e
  ids="$(compose_with_timeout "$DIAGNOSTICS_TIMEOUT" ps -q 2>/dev/null)"
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086
    "$ENGINE" inspect \
      --format 'image|{{.Config.Image}}|{{.Image}}|{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' \
      $ids >>"$file.tmp" 2>/dev/null
  fi
  set -e
  mv "$file.tmp" "$file" 2>/dev/null || true
}

# Reads the exact release version out of the pulled image. The release
# workflow stamps every image with the OCI version label, and suite-api also
# carries NMTK_VERSION, so the installer can pin a mutable `:latest` to the
# immutable tag it actually pulled.
resolve_release_version() {
  local label=""
  set +e
  label="$("$ENGINE" image inspect \
    --format '{{index .Config.Labels "org.opencontainers.image.version"}}' \
    "${SUITE_API_IMAGE}:${IMAGE_TAG}" 2>/dev/null)"
  case "$label" in "" | "<no value>" | latest) label="" ;; esac
  if [ -z "$label" ]; then
    label="$("$ENGINE" image inspect \
      --format '{{range .Config.Env}}{{println .}}{{end}}' \
      "${SUITE_API_IMAGE}:${IMAGE_TAG}" 2>/dev/null |
      sed -n 's/^NMTK_VERSION=//p' | head -n 1)"
  fi
  set -e
  case "$label" in "" | "<no value>" | latest | dev) printf '' ;; *) printf '%s' "$label" ;; esac
}

# Tags the already-pulled images with the resolved version so the start step
# uses the local bits instead of pulling the same layers again.
pin_local_images() {
  local version="$1" repo base
  set +e
  while IFS= read -r repo; do
    case "$repo" in *:*) ;; *) continue ;; esac
    base="${repo%:*}"
    "$ENGINE" tag "${base}:${IMAGE_TAG}" "${base}:${version}" >>"$LOG_FILE" 2>&1
  done < <(compose config 2>/dev/null | sed -n 's/^[[:space:]]*image:[[:space:]]*//p')
  set -e
}

# Restores the recorded images by digest (falling back to their tag) and tags
# each one with ROLLBACK_TAG, which the compose files then pull by.
restore_images_from_state() {
  local file="$1" line ref rest digest repo restored=0
  [ -s "$file" ] || return 1
  while IFS= read -r line; do
    case "$line" in image\|*) ;; *) continue ;; esac
    ref="${line#image|}"
    rest="${ref#*|}"
    ref="${ref%%|*}"
    digest="${rest#*|}"
    case "$digest" in *@sha256:*) ;; *) digest="" ;; esac
    if [ -n "$digest" ]; then
      repo="${digest%@*}"
      if "$ENGINE" pull "$digest" >>"$LOG_FILE" 2>&1 &&
        "$ENGINE" tag "$digest" "${repo}:${ROLLBACK_TAG}" >>"$LOG_FILE" 2>&1; then
        restored=$((restored + 1))
        continue
      fi
    fi
    if [ -n "$ref" ]; then
      repo="${ref%:*}"
      if "$ENGINE" pull "$ref" >>"$LOG_FILE" 2>&1 &&
        "$ENGINE" tag "$ref" "${repo}:${ROLLBACK_TAG}" >>"$LOG_FILE" 2>&1; then
        restored=$((restored + 1))
      fi
    fi
  done <"$file"
  [ "$restored" -gt 0 ]
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
chmod 750 credentials 2>/dev/null || true
if [ ! -s credentials/admin-token ]; then
  umask 027
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32 >credentials/admin-token
  else
    head -c 48 /dev/urandom | base64 | tr -d '\n=' >credentials/admin-token
  fi
fi
# 0644, not 0640: launcher-control reads this file as its unprivileged
# appuser, which lands on the "other" permission bits inside the
# container. The 0750 directory above and the deployment account's own
# home keep it private to this account on the host.
chmod 644 credentials/admin-token

# App-credential logins (launcher_auth.py), additive to admin-token above.
# The file always exists once the stack is up, whether or not
# --app-username/--app-password was passed, because docker-compose.remote.yml
# bind-mounts it unconditionally.
#
# Lives in its own subdirectory, not next to admin-token: when Compose sees
# two file bind mounts sharing the same host source directory, it collapses
# them into a single directory-level bind and applies the strictest of the
# two modes -- so with both files under plain `credentials/`, admin-token's
# `:ro` made users.json read-only too (confirmed on the live dev host: writes
# failed with EROFS despite --user 0:0 and --cap-add DAC_OVERRIDE). A
# separate source directory keeps the two bind mounts distinct.
mkdir -p credentials/app
if [ ! -s credentials/app/users.json ]; then
  umask 027
  printf '{}' >credentials/app/users.json
fi
chmod 644 credentials/app/users.json

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
# Remember what is running before anything is torn down, so a failed update can
# put these exact images back. The pre-update version comes from the live
# backend when it reports one, else from the last-good record.
PREVIOUS_VERSION="$(curl --silent --max-time 5 --fail \
  "http://127.0.0.1:$BACKEND_PORT/api/suite/health" 2>/dev/null |
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)" || true
if [ -z "$PREVIOUS_VERSION" ]; then
  PREVIOUS_VERSION="$(state_value "$LAST_GOOD_STATE" version)"
fi
PREVIOUS_TAG="$(state_value "$LAST_GOOD_STATE" tag)"
[ -n "$PREVIOUS_TAG" ] || PREVIOUS_TAG="$IMAGE_TAG"
capture_running_state "$PENDING_STATE" "$PREVIOUS_TAG" "$PREVIOUS_VERSION"
MIGRATION_DIR=".migration-staging/p0-owner-v1"
MIGRATION_MARKER=".migration-staging/p0-owner-v1.complete"
if [ "$CLEAN_INSTALL" != "true" ] && [ ! -f "$MIGRATION_MARKER" ]; then
  # Any data carried across from the previous stack means this deploy moved
  # data, which forbids automatic rollback even if the release was not flagged.
  MIGRATION_RAN=true
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

# Pinning. The compose files take a mutable `:latest` by default; resolve the
# pulled image to the release version it was stamped with and deploy by that
# immutable tag instead, so a host can name — and later restore — exactly what
# it ran.
PINNED_VERSION="$IMAGE_TAG"
if [ -z "$IMAGE_TAG" ] || [ "$IMAGE_TAG" = "latest" ]; then
  resolved="$(resolve_release_version)"
  if [ -n "$resolved" ]; then
    PINNED_VERSION="$resolved"
    export NMTK_IMAGE_TAG="$PINNED_VERSION"
    pin_local_images "$PINNED_VERSION"
    printf '[nmtk-deploy] Pinned deploy to release %s (requested tag %s).\n' \
      "$PINNED_VERSION" "$IMAGE_TAG" >>"$LOG_FILE"
    write_status pulling_images 55 "Pinned backend release $PINNED_VERSION"
  else
    printf '%s\n' \
      "[nmtk-deploy] WARNING: could not resolve ${IMAGE_TAG} to a release version; deploying the tag as given and relying on recorded digests for rollback." \
      >>"$LOG_FILE"
  fi
fi

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

if [ -n "$APP_USERNAME" ] && [ -n "$APP_PASSWORD" ]; then
  write_status starting_containers 72 "Provisioning app credentials"
  # Hashing happens inside the already-pulled launcher-control image, which
  # already depends on bcrypt for launcher_auth.py, rather than requiring
  # bcrypt on the host. --user 0:0 mirrors the workspace-storage step above,
  # but launcher-control's cap_drop: ALL also strips CAP_DAC_OVERRIDE, so
  # root alone still can't write a file it doesn't own by permission bits --
  # --cap-add DAC_OVERRIDE restores that for this one-off run, the same way
  # --cap-add CHOWN does above. There is deliberately no re-chmod of the file
  # after the write below: that would need CAP_FOWNER, also stripped by
  # cap_drop: ALL, and is unnecessary anyway -- install.sh already left the
  # file at 0644 above, and writing to an existing file never changes its
  # mode bits.
  if ! NMTK_PROVISION_APP_USERNAME="$APP_USERNAME" \
    NMTK_PROVISION_APP_PASSWORD="$APP_PASSWORD" \
    compose run --rm --no-deps --user 0:0 \
    --cap-add DAC_OVERRIDE \
    -e NMTK_PROVISION_APP_USERNAME -e NMTK_PROVISION_APP_PASSWORD \
    --entrypoint python3 launcher-control -c '
import bcrypt, json, os

path = "/app/credentials/users.json"
try:
    with open(path, encoding="utf-8") as f:
        users = json.load(f)
except (OSError, ValueError):
    users = {}
if not isinstance(users, dict):
    users = {}

username = os.environ["NMTK_PROVISION_APP_USERNAME"]
password = os.environ["NMTK_PROVISION_APP_PASSWORD"].encode("utf-8")
users[username] = bcrypt.hashpw(password, bcrypt.gensalt()).decode("utf-8")

with open(path, "w", encoding="utf-8") as f:
    json.dump(users, f)
' >>"$LOG_FILE" 2>&1; then
    fail_stage "The app-credential login could not be provisioned; diagnostics were captured in the deployment log."
  fi
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
if ! health_probe "http://127.0.0.1:$BACKEND_PORT/api/suite/health"; then
  fail_stage "Suite API did not become ready within ${HEALTH_ATTEMPTS} checks; diagnostics were captured in the deployment log."
fi

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
if ! health_probe "http://127.0.0.1:8090/health"; then
  fail_stage "Launcher control did not become ready within ${HEALTH_ATTEMPTS} checks; diagnostics were captured in the deployment log."
fi

# /health is public. Every other launcher endpoint needs the administrator
# token, and launcher-control reads it from a file mounted into the container:
# if that file is unreadable there, it answers 401 to a perfectly correct
# token and the stack looks healthy while the app cannot use it at all. Prove
# the credential works here rather than letting the client discover it as
# "the backend is unreachable".
launcher_auth_code="$(curl --silent --output /dev/null --max-time 10 \
  --write-out '%{http_code}' \
  --header "X-NMTK-Admin-Token: $(cat credentials/admin-token)" \
  "http://127.0.0.1:8090/api/launcher/settings" 2>>"$LOG_FILE")"
case "$launcher_auth_code" in
  2*) ;;
  401 | 403)
    fail_stage "Launcher control rejected its own administrator token, so it cannot read the mounted credential file. Check that credentials/admin-token is world-readable and mounted into the launcher-control container."
    ;;
  *)
    fail_stage "Launcher control did not answer an authenticated request (HTTP $launcher_auth_code)."
    ;;
esac

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

# This image set verified, so it becomes the one a future rollback restores.
capture_running_state "$LAST_GOOD_STATE" "$PINNED_VERSION" "$PINNED_VERSION"
rm -f "$PENDING_STATE"

write_status completed 100 "Backend and launcher control are ready"
