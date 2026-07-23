#!/usr/bin/env bash
set -u

remote_host="${REMOTE_HOST:?REMOTE_HOST is required}"
deploy_dir="${DEPLOY_DIR:-~/nmtk-deploy}"
launcher_control_port="${LAUNCHER_CONTROL_PORT:-8090}"
ssh_opts="${SSH_OPTS:-}"
remote_ip="${remote_host#*@}"
compose_file_args="${COMPOSE_FILE_ARGS:-}"
neurochip_hw_worker_api_key="${NEUROCHIP_HW_WORKER_API_KEY:-}"

compose_cmd="cd ${deploy_dir} && BUILDKIT_STEP_LOG_MAX_SIZE=-1 DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 LAUNCHER_CONTROL_PORT=${launcher_control_port} JUPYTER_PUBLIC_URL=http://${remote_ip}:8008/lab NEUROCHIP_HW_WORKER_API_KEY=${neurochip_hw_worker_api_key} docker compose ${compose_file_args} up --build -d --wait --remove-orphans"
repair_cmd="cd ${deploy_dir} && { docker compose rm -sf suite_api 2>/dev/null || true; docker image rm -f nmtk-deploy-suite_api:latest neuromorphictoolkit-suite_api:latest 2>/dev/null || true; docker builder prune -f --keep-storage=20GB; }"

log_file="$(mktemp)"
cleanup() {
  rm -f "${log_file}"
}
trap cleanup EXIT

run_remote() {
  # shellcheck disable=SC2086
  ssh ${ssh_opts} "${remote_host}" "$1"
}

run_remote "${compose_cmd}" 2>&1 | tee "${log_file}"
status=${PIPESTATUS[0]}

if [ "${status}" -eq 0 ]; then
  exit 0
fi

if ! grep -q "invalid tar header" "${log_file}"; then
  exit "${status}"
fi

echo "==> Docker image export hit 'invalid tar header'; pruning stale builder cache and retrying once..."
if ! run_remote "${repair_cmd}"; then
  echo "Remote Docker cache repair failed; rerun with direct SSH access and inspect Docker daemon storage." >&2
  exit "${status}"
fi

run_remote "${compose_cmd}"
