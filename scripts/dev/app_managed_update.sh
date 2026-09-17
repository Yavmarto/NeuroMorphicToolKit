#!/usr/bin/env bash
# Replace selected services in the app-owned rootless Podman stack with images
# built by make dev-update. Runs as root because the normal developer SSH user
# cannot access another account's rootless Podman socket.

set -euo pipefail

HELPER_VERSION="2"
HELPER_SOURCE="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
# A privilege drop inherits its caller's working directory. The developer SSH
# account's home is intentionally private, so runuser cannot even start there.
# Everything below uses absolute paths or changes into the deployment directory.
cd /

DEPLOY_USER="${NMTK_APP_DEPLOY_USER:-nmtk-deploy}"
DEPLOY_HOME="${NMTK_APP_DEPLOY_HOME:-$(getent passwd "$DEPLOY_USER" | cut -d: -f6)}"
DEPLOY_UID="${NMTK_APP_DEPLOY_UID:-$(id -u "$DEPLOY_USER")}"
DEPLOY_DIR="${NMTK_APP_DEPLOY_DIR:-$DEPLOY_HOME/.nmtk/deploy}"
TESTING="${NMTK_APP_UPDATE_TESTING:-0}"
if [ "$TESTING" = "1" ]; then
  INSTALLED_HELPER="${NMTK_APP_UPDATE_INSTALLED_HELPER:-/usr/local/libexec/nmtk-app-managed-update}"
  SUDOERS_FILE="${NMTK_APP_UPDATE_SUDOERS_FILE:-/etc/sudoers.d/nmtk-dev-update}"
else
  INSTALLED_HELPER="/usr/local/libexec/nmtk-app-managed-update"
  SUDOERS_FILE="/etc/sudoers.d/nmtk-dev-update"
fi

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if [ "${1:-}" = "--version" ]; then
  printf 'nmtk-app-managed-update %s\n' "$HELPER_VERSION"
  exit 0
fi

if [ "$TESTING" != "1" ] && [ "$(id -u)" -ne 0 ]; then
  fail "app-managed backend updates require administrator access"
fi

[ -n "$DEPLOY_HOME" ] && [ "$DEPLOY_HOME" != "/" ] ||
  fail "the $DEPLOY_USER account has no safe home directory"
[ -d "$DEPLOY_DIR" ] ||
  fail "the app-managed deployment was not found at $DEPLOY_DIR"
for compose_file in docker-compose.yml docker-compose.prod.yml docker-compose.remote.yml; do
  [ -f "$DEPLOY_DIR/$compose_file" ] ||
    fail "the app-managed deployment is missing $compose_file"
done

install_passwordless_helper() {
  local caller="$1" sudoers_dir sudoers_tmp
  case "$caller" in
    *[!a-zA-Z0-9_.-]*|'') fail "invalid developer account name: $caller" ;;
  esac
  if [ "$TESTING" != "1" ] && ! id "$caller" >/dev/null 2>&1; then
    fail "developer account $caller does not exist"
  fi
  case "$INSTALLED_HELPER" in
    /*) ;;
    *) fail "the installed helper path must be absolute" ;;
  esac
  case "$INSTALLED_HELPER" in
    *[[:space:]]*) fail "the installed helper path cannot contain spaces" ;;
  esac

  install -d -m 0755 "$(dirname "$INSTALLED_HELPER")"
  install -m 0755 "$HELPER_SOURCE" "$INSTALLED_HELPER"

  sudoers_dir="$(dirname "$SUDOERS_FILE")"
  install -d -m 0755 "$sudoers_dir"
  sudoers_tmp="$(mktemp "$sudoers_dir/.nmtk-dev-update.XXXXXX")"
  printf '%s ALL=(root) NOPASSWD: %s *\n' \
    "$caller" "$INSTALLED_HELPER" >"$sudoers_tmp"
  chmod 0440 "$sudoers_tmp"
  if [ "$TESTING" != "1" ]; then
    visudo -cf "$sudoers_tmp" >/dev/null || {
      rm -f -- "$sudoers_tmp"
      fail "could not validate the scoped dev-update permission"
    }
  fi
  install -m 0440 "$sudoers_tmp" "$SUDOERS_FILE"
  rm -f -- "$sudoers_tmp"
  printf '==> Future developer updates can reuse the scoped app-update helper.\n'
}

if [ "${1:-}" = "--install-for" ]; then
  [ "$#" -ge 2 ] || fail "--install-for needs a developer account name"
  install_passwordless_helper "$2"
  shift 2
  [ "$#" -gt 0 ] || exit 0
fi

run_as_deploy() {
  if [ "$TESTING" = "1" ]; then
    env HOME="$DEPLOY_HOME" XDG_RUNTIME_DIR="/run/user/$DEPLOY_UID" "$@"
    return
  fi
  runuser -u "$DEPLOY_USER" -- \
    env HOME="$DEPLOY_HOME" XDG_RUNTIME_DIR="/run/user/$DEPLOY_UID" "$@"
}

podman_compose() {
  run_as_deploy bash -c '
    deploy_dir="$1"
    shift
    cd "$deploy_dir"
    exec "$@"
  ' _ "$DEPLOY_DIR" podman compose --project-name nmtk \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    -f docker-compose.remote.yml "$@"
}

container_for_service() {
  local service="$1" ids
  ids="$(
    {
      run_as_deploy podman ps -aq \
        --filter label=com.docker.compose.project=nmtk \
        --filter "label=com.docker.compose.service=$service"
      run_as_deploy podman ps -aq \
        --filter label=io.podman.compose.project=nmtk \
        --filter "label=io.podman.compose.service=$service"
    } | awk 'NF' | sort -u
  )"
  [ "$(printf '%s\n' "$ids" | awk 'NF {count++} END {print count+0}')" -eq 1 ] ||
    fail "expected exactly one app-managed $service container"
  printf '%s' "$ids"
}

probe_url_for_service() {
  case "$1" in
    launcher-control) printf 'http://127.0.0.1:8091/health\n' ;;
    suite_api) printf 'http://127.0.0.1:9000/api/suite/health\n' ;;
    neurosense-hw-worker) printf 'http://127.0.0.1:8004/health\n' ;;
    neurobench-runner-worker) printf 'http://127.0.0.1:8003/health\n' ;;
    neurochip-hw-worker) printf 'http://127.0.0.1:8002/health\n' ;;
    lava-backend) printf 'http://127.0.0.1:8012/health\n' ;;
    neurocnl-physics-worker) printf 'http://127.0.0.1:8006/health\n' ;;
    snn-mlir-compiler) printf 'http://127.0.0.1:8007/health\n' ;;
    jupyter-server) printf 'http://127.0.0.1:8008/api/status\n' ;;
    *) return 1 ;;
  esac
}

probe_service() {
  local service="$1" container_id="$2" url
  url="$(probe_url_for_service "$service")" || return 1
  run_as_deploy podman exec "$container_id" python -c \
    'import sys, urllib.request; response = urllib.request.urlopen(sys.argv[1], timeout=5); sys.exit(0 if 200 <= response.status < 400 else 1)' \
    "$url" >/dev/null 2>&1
}

wait_for_service() {
  local service="$1" container_id status
  for _attempt in $(seq 1 90); do
    container_id="$(container_for_service "$service")"
    status="$(
      run_as_deploy podman inspect --format '{{.State.Status}}' "$container_id"
    )"
    case "$status" in
      running)
        # Podman 5.7's external Docker Compose provider corrupts array-form
        # health commands (`python -c "..."`) into separate arguments. Probe
        # the real in-container HTTP endpoint instead of trusting that broken
        # health metadata.
        probe_service "$service" "$container_id" && return 0
        ;;
      unhealthy|exited|dead) return 1 ;;
    esac
    sleep 2
  done
  return 1
}

report_service_failure() {
  local service="$1" container_id
  container_id="$(container_for_service "$service")" || return 0
  printf '%s\n' "--- $service container state ---" >&2
  run_as_deploy podman inspect --format \
    'status={{.State.Status}} health={{json .State.Health}}' \
    "$container_id" >&2 || true
  printf '%s\n' "--- $service logs (last 80 lines) ---" >&2
  run_as_deploy podman logs --tail 80 "$container_id" >&2 || true
}

cleanup_archives=()
cleanup() {
  local archive
  for archive in "${cleanup_archives[@]-}"; do
    case "$archive" in
      /tmp/nmtk-dev-update.*/*.tar) rm -f -- "$archive" ;;
    esac
  done
}
trap cleanup EXIT

[ "$#" -gt 0 ] && [ $(( $# % 3 )) -eq 0 ] ||
  fail "expected SERVICE ARCHIVE SOURCE_TAG groups"

while [ "$#" -gt 0 ]; do
  service="$1"
  archive="$2"
  source_tag="$3"
  shift 3

  case "$service" in
    *[!a-zA-Z0-9_-]*|'') fail "invalid Compose service name: $service" ;;
  esac
  case "$archive" in
    /tmp/nmtk-dev-update.*/*.tar) ;;
    *) fail "refusing image archive outside the dev-update temporary directory" ;;
  esac
  [ -f "$archive" ] || fail "image archive is missing for $service"
  cleanup_archives+=("$archive")

  container_id="$(container_for_service "$service")"
  target_image="$(
    run_as_deploy podman inspect --format '{{.ImageName}}' "$container_id"
  )"
  [ -n "$target_image" ] || fail "could not identify the current $service image"
  previous_image="$(
    run_as_deploy podman inspect --format '{{.Image}}' "$container_id"
  )"
  [ -n "$previous_image" ] || fail "could not identify the current $service image ID"

  printf '==> Loading development image for %s into the app-owned Podman stack...\n' \
    "$service"
  run_as_deploy podman load -i "$archive"
  run_as_deploy podman tag "$source_tag" "$target_image"

  image_tag="${target_image##*:}"
  [ "$image_tag" != "$target_image" ] || image_tag="latest"
  if NMTK_IMAGE_TAG="$image_tag" podman_compose \
      up -d --no-deps --force-recreate "$service" && \
     wait_for_service "$service"; then
    printf '==> %s is healthy.\n' "$service"
    continue
  fi

  printf '==> New %s image failed health verification; restoring the previous image.\n' \
    "$service" >&2
  report_service_failure "$service"
  run_as_deploy podman tag "$previous_image" "$target_image"
  NMTK_IMAGE_TAG="$image_tag" podman_compose \
    up -d --no-deps --force-recreate "$service" || true
  wait_for_service "$service" || true
  fail "$service did not become healthy; the previous image was restored"
done

printf '==> App-owned backend services updated.\n'
