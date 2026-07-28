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

write_status() {
  CURRENT_STAGE="$1"
  printf '%s|%s|%s\n' "$1" "$2" "$3" >"$STATUS_FILE"
  printf '[nmtk-deploy] %s\n' "$3" >>"$LOG_FILE"
}

capture_failure_diagnostics() {
  printf '%s\n' '[nmtk-deploy] Capturing container diagnostics.' >>"$LOG_FILE"
  printf '%s\n' '[nmtk-deploy] Container state:' >>"$LOG_FILE"
  compose ps -a >>"$LOG_FILE" 2>&1 || true
  printf '%s\n' '[nmtk-deploy] Suite API and launcher-control logs:' >>"$LOG_FILE"
  compose logs --tail 200 suite_api launcher-control >>"$LOG_FILE" 2>&1 || true
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

compose() {
  "$ENGINE" compose \
    --project-name nmtk \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    -f docker-compose.remote.yml \
    "$@"
}

trap handle_failure ERR

export SUITE_API_PORT="$BACKEND_PORT"
export LAUNCHER_CONTROL_PORT=8090
export NMTK_IMAGE_TAG="$IMAGE_TAG"
export JUPYTER_PUBLIC_URL="http://$PUBLIC_HOST:8008/lab"

write_status preflight_running 10 "Validating container provider"
"$ENGINE" info >>"$LOG_FILE" 2>&1
compose config --quiet >>"$LOG_FILE" 2>&1

if [ "$CLEAN_INSTALL" = "true" ]; then
  write_status installing_prerequisites 20 "Removing existing data volumes"
  compose down -v --remove-orphans >>"$LOG_FILE" 2>&1 || true
else
  compose down --remove-orphans >>"$LOG_FILE" 2>&1 || true
fi

write_status pulling_images 45 "Pulling backend images"
compose pull >>"$LOG_FILE" 2>&1

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
compose up -d --remove-orphans >>"$LOG_FILE" 2>&1

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

write_status completed 100 "Backend and launcher control are ready"
