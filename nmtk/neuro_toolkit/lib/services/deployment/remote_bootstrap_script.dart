/// The shell script executed on a remote host to bootstrap the NMTK
/// deployment account: engine install, container/volume cleanup, and
/// deployment-credential generation. Pure function of its two parameters —
/// no instance state, safe to call from anywhere.
String buildRemoteBootstrapScript({
  required String containerEngine,
  required bool factoryReset,
}) {
  final resetFlag = factoryReset ? 'true' : 'false';
  return r'''
set -euo pipefail
# Every privilege drop below (runuser/env, and any added later) inherits this
# shell's working directory, and runuser does not change it. The SSH login lands
# in the administrator's home, which other accounts cannot traverse on modern
# distributions, so a dropped-privilege child fails before it can even start.
# "/" is traversable by every account. Nothing in this script uses a relative
# path, so moving here is safe.
cd /
ENGINE="__ENGINE__"
FACTORY_RESET="__FACTORY_RESET__"
DEPLOY_USER="nmtk-deploy"
DEPLOY_GROUP="$DEPLOY_USER"
PROJECTS="nmtk nmtk-deploy deploy"
CURRENT_PHASE="preflight_running"
RUNTIME_BASE="${NMTK_SETUP_RUNTIME_BASE:-/run/user}"
TEMP_RUNTIME_DIRS=()
TEMP_COMMAND_DIRS=()
TEMPORARY_KEY_DIR=""

phase() {
  CURRENT_PHASE="$1"
  printf 'NMTK_SETUP_PHASE|%s|%s|%s\n' "$1" "$2" "$3"
}
fail() {
  code="$1"
  exit_code="$2"
  message="$3"
  trap - ERR
  printf 'NMTK_SETUP_ERROR|%s|%s|%s|%s\n' \
    "$code" "$CURRENT_PHASE" "$exit_code" "$message" >&2
  exit "$exit_code"
}
trap 'exit_code=$?; printf "NMTK_SETUP_ERROR|unexpected_setup_failure|%s|%s|A server command failed unexpectedly.\\n" "$CURRENT_PHASE" "$exit_code" >&2' ERR

terminal() {
  printf 'NMTK_SETUP_TERMINAL|%s\n' "$1"
}
command_marker() {
  printf 'NMTK_SETUP_COMMAND|%s\n' "$1"
}
command_exit_marker() {
  printf 'NMTK_SETUP_COMMAND_EXIT|%s|%s\n' "$1" "$2"
}
step_marker() {
  printf 'NMTK_SETUP_STEP|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"
}
# Announces that the script itself is finished. The client treats this as the
# authoritative end of the administrator session: rootless Podman leaves
# lingering processes that inherit this SSH channel, so waiting for channel EOF
# would hang forever even though setup succeeded.
done_marker() {
  printf 'NMTK_SETUP_DONE|%s\n' "$1"
}
cleanup_temporary_setup_files() {
  exit_code="$?"
  trap - EXIT
  cleanup_failed=0
  key_cleanup_failed=0
  cleanup_user=""
  for runtime_entry in "${TEMP_RUNTIME_DIRS[@]-}"; do
    [ -n "$runtime_entry" ] || continue
    runtime_user="${runtime_entry%%:*}"
    runtime_dir="${runtime_entry#*:}"
    [ -n "$runtime_dir" ] || continue
    case "$runtime_dir" in
      /tmp/nmtk-podman-runtime.*)
        set +e
        timeout --signal=TERM --kill-after=5s 30s \
          rm -rf -- "$runtime_dir"
        cleanup_exit="$?"
        set -e
        if [ "$cleanup_exit" -ne 0 ]; then
          cleanup_failed=1
          cleanup_user="$runtime_user"
          terminal "✗ Temporary Podman runtime cleanup failed for user $runtime_user"
        fi
        ;;
      esac
  done
  if [ -n "$TEMPORARY_KEY_DIR" ]; then
    case "$TEMPORARY_KEY_DIR" in
      /tmp/nmtk-deploy-key.*)
        set +e
        timeout --signal=TERM --kill-after=5s 30s \
          rm -rf -- "$TEMPORARY_KEY_DIR"
        key_cleanup_exit="$?"
        set -e
        if [ "$key_cleanup_exit" -ne 0 ]; then
          cleanup_failed=1
          key_cleanup_failed=1
          terminal "✗ Temporary deployment credential cleanup failed"
        fi
        ;;
      esac
  fi
  for command_dir in "${TEMP_COMMAND_DIRS[@]-}"; do
    case "$command_dir" in
      /tmp/nmtk-command-output.*)
        rm -rf -- "$command_dir" 2>/dev/null || true
        ;;
    esac
  done
  if [ "$cleanup_failed" -eq 1 ] && [ "$exit_code" -eq 0 ]; then
    if [ "$key_cleanup_failed" -eq 1 ]; then
      printf 'NMTK_SETUP_ERROR|deploy_account_failed|%s|26|%s\n' \
        "$CURRENT_PHASE" \
        "The temporary deployment credential directory could not be removed." >&2
      done_marker 26
      exit 26
    else
      printf 'NMTK_SETUP_ERROR|podman_inspection_failed|%s|29|%s\n' \
        "$CURRENT_PHASE" \
        "Administrator access succeeded, but the temporary Podman runtime for user $cleanup_user could not be removed." >&2
      done_marker 29
      exit 29
    fi
  fi
  done_marker "$exit_code"
  exit "$exit_code"
}
trap cleanup_temporary_setup_files EXIT
STEP_OUTPUT=""
STEP_ERROR=""
STEP_EXIT=0
# Set to 1 only while inspecting a third-party account's rootless Podman.
RUNTIME_SWEEP_OPTIONAL=0
SKIPPED_PODMAN_ACCOUNTS=""
terminate_residual_command_group() {
  local group_pid="$1"
  kill -TERM -- "-$group_pid" 2>/dev/null || return 0
  for _ in {1..20}; do
    kill -0 -- "-$group_pid" 2>/dev/null || return 0
    sleep 0.05
  done
  kill -KILL -- "-$group_pid" 2>/dev/null || true
}

drain_capture_streams() {
  local stdout_pid="$1"
  local stderr_pid="$2"
  local stdout_forced=0
  local stderr_forced=0
  local stdout_alive=0
  local stderr_alive=0

  for _ in {1..40}; do
    stdout_alive=0
    stderr_alive=0
    kill -0 "$stdout_pid" 2>/dev/null && stdout_alive=1
    kill -0 "$stderr_pid" 2>/dev/null && stderr_alive=1
    [ "$stdout_alive" -eq 0 ] && [ "$stderr_alive" -eq 0 ] && break
    sleep 0.05
  done
  if kill -0 "$stdout_pid" 2>/dev/null; then
    stdout_forced=1
    kill -TERM "$stdout_pid" 2>/dev/null || true
  fi
  if kill -0 "$stderr_pid" 2>/dev/null; then
    stderr_forced=1
    kill -TERM "$stderr_pid" 2>/dev/null || true
  fi

  wait "$stdout_pid"
  stdout_tee_exit="$?"
  wait "$stderr_pid"
  stderr_tee_exit="$?"
  [ "$stdout_forced" -eq 0 ] || stdout_tee_exit=0
  [ "$stderr_forced" -eq 0 ] || stderr_tee_exit=0
}

# Runs one step and records its exit code in STEP_EXIT without judging it. The
# two wrappers below decide whether a non-zero exit ends the whole setup
# (capture_step) or only the account currently being swept
# (capture_optional_step).
run_capture_step() {
  seconds="$1"
  display="$2"
  shift 2
  automatic_recovery="${NMTK_SETUP_AUTOMATIC_RECOVERY:-false}"
  step_marker start "$seconds" "$automatic_recovery" "$display"
  printf -v rendered_command '%q ' "$@"
  rendered_command="${rendered_command% }"
  command_marker "$rendered_command"
  output_dir="$(mktemp -d /tmp/nmtk-command-output.XXXXXX)"
  TEMP_COMMAND_DIRS+=("$output_dir")
  stdout_file="$output_dir/stdout"
  stderr_file="$output_dir/stderr"
  stdout_pipe="$output_dir/stdout.pipe"
  stderr_pipe="$output_dir/stderr.pipe"
  mkfifo "$stdout_pipe" "$stderr_pipe"
  tee "$stdout_file" <"$stdout_pipe" &
  stdout_tee_pid="$!"
  tee "$stderr_file" <"$stderr_pipe" >&2 &
  stderr_tee_pid="$!"
  set +e
  timeout --signal=TERM --kill-after=5s "${seconds}s" "$@" \
    </dev/null >"$stdout_pipe" 2>"$stderr_pipe" &
  command_group_pid="$!"
  wait "$command_group_pid"
  command_exit="$?"
  terminate_residual_command_group "$command_group_pid"
  drain_capture_streams "$stdout_tee_pid" "$stderr_tee_pid"
  set -e
  STEP_OUTPUT="$(cat "$stdout_file")"
  STEP_ERROR="$(cat "$stderr_file")"
  rm -rf -- "$output_dir"
  if [ "$stdout_tee_exit" -ne 0 ] || [ "$stderr_tee_exit" -ne 0 ]; then
    fail "unexpected_setup_failure" 28 \
      "The server output stream could not be captured."
  fi
  STEP_EXIT="$command_exit"
  step_marker finish "$seconds" "$automatic_recovery" "$display"
  if [ "$command_exit" -ne 0 ]; then
    if [ "$command_exit" -eq 124 ]; then
      command_exit_marker timeout "$seconds"
    else
      command_exit_marker exit "$command_exit"
    fi
  fi
}

capture_step() {
  code="$2"
  failure_exit="$3"
  step_display="$4"
  run_capture_step "$1" "$4" "${@:6}"
  if [ "$STEP_EXIT" -ne 0 ]; then
    fail "$code" "$failure_exit" "$step_display failed or timed out."
  fi
}

# Same capture, but a non-zero exit is reported to the caller instead of ending
# setup. Used only while sweeping other accounts' rootless Podman storage, where
# one unreadable account must not block the whole server.
capture_optional_step() {
  run_capture_step "$1" "$2" "${@:3}"
  [ "$STEP_EXIT" -eq 0 ]
}

validated_container_ids() {
  local input="$1"
  local context="$2"
  local valid
  valid="$(printf '%s\n' "$input" |
    awk 'NF && $0 ~ /^[0-9a-fA-F]+$/ &&
      length($0) >= 12 && length($0) <= 64 {print}' | sort -u)"
  malformed="$(printf '%s\n' "$input" |
    awk 'NF && ($0 !~ /^[0-9a-fA-F]+$/ ||
      length($0) < 12 || length($0) > 64) {print; exit}')"
  if [ -n "$malformed" ]; then
    [ "$RUNTIME_SWEEP_OPTIONAL" -eq 0 ] || return 1
    fail "podman_inspection_failed" 29 \
      "$context returned an invalid container identifier."
  fi
  printf '%s' "$valid"
}

validated_volume_names() {
  local input="$1"
  local context="$2"
  local valid
  valid="$(printf '%s\n' "$input" |
    awk 'NF && $0 ~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/ {print}' | sort -u)"
  malformed="$(printf '%s\n' "$input" |
    awk 'NF && $0 !~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/ {print; exit}')"
  if [ -n "$malformed" ]; then
    [ "$RUNTIME_SWEEP_OPTIONAL" -eq 0 ] || return 1
    fail "volume_cleanup_failed" 31 \
      "$context returned an invalid volume name."
  fi
  printf '%s' "$valid"
}

if [ "$(id -u)" -ne 0 ]; then
  terminal "✗ Administrator privileges were not granted"
  fail "sudo_access_denied" 19 \
    "The setup shell is not running with administrator privileges."
fi
terminal "✓ Administrator privileges confirmed"

phase "preflight_running" 7 "Checking server compatibility"
capture_step 30 "unsupported_os" 20 "Checking server operating system" \
  "Server operating system identified" uname -s
[ "$STEP_OUTPUT" = "Linux" ] || {
  terminal "✗ Linux is required; found $STEP_OUTPUT"
  fail "unsupported_os" 20 "Linux is required."
}
capture_step 30 "insufficient_disk" 21 "Checking free disk space" \
  "Disk capacity checked" df -Pk /
AVAILABLE_KB="$(printf '%s\n' "$STEP_OUTPUT" | awk 'NR==2 {print $4}')"
[ "${AVAILABLE_KB:-0}" -ge 5242880 ] || {
  terminal "✗ Less than 5 GB is available on the server"
  fail "insufficient_disk" 21 "At least 5 GB of free disk space is required."
}

# Read-only inspection step. Takes the same arguments as capture_step, but while
# RUNTIME_SWEEP_OPTIONAL is set it reports failure to the caller instead of
# ending setup, so an unreadable third-party account is skipped rather than
# treated as a broken server. Destructive steps never go through here.
inspect_step() {
  if [ "$RUNTIME_SWEEP_OPTIONAL" -eq 1 ]; then
    capture_optional_step "$1" "$4" "${@:6}"
  else
    capture_step "$@"
  fi
}

remove_runtime_objects() {
  local runtime="$1"
  local context="$2"
  shift 2
  command -v "$runtime" >/dev/null 2>&1 || return 0
  if [ "$runtime" = "docker" ]; then
    inspect_step 20 "${runtime}_inspection_failed" 29 \
      "Checking $context access" "$context is accessible" \
      "$@" "$runtime" info --format \
      'version={{.ServerVersion}} rootless=false storage={{.DockerRootDir}}' ||
      return 1
  else
    inspect_step 20 "${runtime}_inspection_failed" 29 \
      "Checking $context access" "$context is accessible" \
      "$@" "$runtime" info --format \
      'version={{.Version.Version}} rootless={{.Host.Security.Rootless}} storage={{.Store.GraphRoot}}' ||
      return 1
  fi
  inspect_step 60 "${runtime}_inspection_failed" 29 \
    "Inspecting $context containers" "$context containers inspected" \
    "$@" "$runtime" ps -a --format '{{.ID}} {{.Names}}' || return 1
  known_ids="$(printf '%s\n' "$STEP_OUTPUT" |
    awk '$1 ~ /^[0-9a-fA-F]+$/ &&
      length($1) >= 12 && length($1) <= 64 &&
      $2 ~ /^(nmtk|nmtk-deploy|deploy)[_-](suite_api|neurosense-hw-worker|neurobench-runner-worker|neurochip-hw-worker|lava-backend|launcher-control|neurocnl-physics-worker|snn-mlir-compiler|jupyter-server)([-_][0-9]+)?$/ {print $1}')"
  if [ -n "$known_ids" ]; then
    known_id_list=()
    while IFS= read -r object_id; do
      [ -n "$object_id" ] && known_id_list+=("$object_id")
    done <<<"$known_ids"
    capture_step 60 "container_cleanup_failed" 30 \
      "Removing known NMTK $runtime containers" \
      "Known NMTK $runtime containers removed" \
      "$@" "$runtime" rm -f "${known_id_list[@]}"
  fi
  for project in $PROJECTS; do
    inspect_step 60 "${runtime}_inspection_failed" 29 \
      "Inspecting NMTK $runtime project $project" \
      "$context project $project inspected" \
      "$@" "$runtime" ps -aq \
      --filter "label=com.docker.compose.project=$project" || return 1
    ids="$STEP_OUTPUT"
    inspect_step 60 "${runtime}_inspection_failed" 29 \
      "Inspecting legacy NMTK $runtime project $project" \
      "$context legacy project $project inspected" \
      "$@" "$runtime" ps -aq \
      --filter "label=io.podman.compose.project=$project" || return 1
    ids="$ids
$STEP_OUTPUT"
    ids="$(validated_container_ids "$ids" \
      "$context project $project inspection")" || {
      # The validator runs in a subshell, so its own exit cannot end the script.
      validation_exit="$?"
      [ "$RUNTIME_SWEEP_OPTIONAL" -eq 1 ] && return 1
      exit "$validation_exit"
    }
    if [ -n "$ids" ]; then
      id_list=()
      while IFS= read -r object_id; do
        [ -n "$object_id" ] && id_list+=("$object_id")
      done <<<"$ids"
      capture_step 60 "container_cleanup_failed" 30 \
        "Removing NMTK $runtime project $project" \
        "NMTK $runtime project $project removed" \
        "$@" "$runtime" rm -f "${id_list[@]}"
    fi
    if [ "$FACTORY_RESET" = "true" ]; then
      inspect_step 60 "${runtime}_inspection_failed" 29 \
        "Inspecting NMTK $runtime data for project $project" \
        "$context project $project volumes inspected" \
        "$@" "$runtime" volume ls -q \
        --filter "label=com.docker.compose.project=$project" || return 1
      volumes="$STEP_OUTPUT"
      inspect_step 60 "${runtime}_inspection_failed" 29 \
        "Inspecting legacy NMTK $runtime data for project $project" \
        "$context legacy project $project volumes inspected" \
        "$@" "$runtime" volume ls -q \
        --filter "label=io.podman.compose.project=$project" || return 1
      volumes="$volumes
$STEP_OUTPUT"
      volumes="$(validated_volume_names "$volumes" \
        "$context project $project volume inspection")" || {
        validation_exit="$?"
        [ "$RUNTIME_SWEEP_OPTIONAL" -eq 1 ] && return 1
        exit "$validation_exit"
      }
      if [ -n "$volumes" ]; then
        volume_list=()
        while IFS= read -r volume_name; do
          [ -n "$volume_name" ] && volume_list+=("$volume_name")
        done <<<"$volumes"
        capture_step 60 "volume_cleanup_failed" 31 \
          "Erasing NMTK $runtime data for project $project" \
          "NMTK $runtime volumes removed" \
          "$@" "$runtime" volume rm -f "${volume_list[@]}"
      fi
    fi
  done
}

phase "reconciling_existing_install" 10 \
  "Removing existing NMTK containers"
if command -v docker >/dev/null 2>&1; then
  capture_step 30 "docker_inspection_failed" 29 "Starting Docker service" \
    "Docker service started" systemctl start docker
  remove_runtime_objects docker docker
fi
if command -v podman >/dev/null 2>&1; then
  remove_runtime_objects podman podman
  while IFS=: read -r candidate _ uid gid _ home _; do
    [ "$uid" -ge 1000 ] 2>/dev/null || continue
    [ -d "$home" ] || continue

    configured_storage="$home/.config/containers/storage.conf"
    default_storage="$home/.local/share/containers/storage"
    active_runtime="$RUNTIME_BASE/$uid"
    if [ ! -e "$configured_storage" ] &&
       [ ! -d "$default_storage" ] &&
       [ ! -S "$active_runtime/podman/podman.sock" ] &&
       [ ! -d "$active_runtime/libpod" ]; then
      continue
    fi

    # Everything below concerns somebody else's rootless Podman. A problem here
    # says nothing about whether this server can host NMTK, so the account is
    # skipped and named instead of failing the whole setup.
    RUNTIME_SWEEP_OPTIONAL=1
    skip_candidate=0
    runtime_dir="$active_runtime"
    if [ -d "$runtime_dir" ]; then
      runtime_owner="$(stat -c '%u' "$runtime_dir" 2>/dev/null || true)"
      if [ "$runtime_owner" != "$uid" ]; then
        skip_candidate=1
      fi
    elif capture_optional_step 30 \
        "Preparing Podman access for user $candidate" \
        mktemp -d "/tmp/nmtk-podman-runtime.${uid}.XXXXXX"; then
      runtime_dir="$STEP_OUTPUT"
      TEMP_RUNTIME_DIRS+=("$candidate:$runtime_dir")
      capture_optional_step 30 \
        "Securing Podman access for user $candidate" \
        bash -c 'chown "$1:$2" "$3" && chmod 700 "$3"' \
        _ "$uid" "$gid" "$runtime_dir" || skip_candidate=1
    else
      skip_candidate=1
    fi

    if [ "$skip_candidate" -eq 0 ]; then
      remove_runtime_objects podman "podman (user $candidate)" \
        runuser -u "$candidate" -- \
        env "HOME=$home" "XDG_RUNTIME_DIR=$runtime_dir" || skip_candidate=1
    fi
    RUNTIME_SWEEP_OPTIONAL=0

    if [ "$skip_candidate" -eq 1 ]; then
      SKIPPED_PODMAN_ACCOUNTS="$SKIPPED_PODMAN_ACCOUNTS $candidate"
      printf 'Could not read the Podman setup of account %s; its containers were left in place.\n' \
        "$candidate"
    fi
  done </etc/passwd
  if [ -n "$SKIPPED_PODMAN_ACCOUNTS" ]; then
    printf 'Skipped Podman accounts:%s\n' "$SKIPPED_PODMAN_ACCOUNTS"
  fi
fi

phase "installing_prerequisites" 13 "Preparing $ENGINE"
case "$ENGINE" in
  docker)
    if ! command -v docker >/dev/null 2>&1; then
      command -v curl >/dev/null 2>&1 ||
        capture_step 300 "engine_install_failed" 24 \
          "Installing server download support" "curl installed" \
          bash -c 'apt-get update -qq &&
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl'
      capture_step 300 "engine_install_failed" 24 \
        "Installing Docker Engine" "Docker Engine installed" \
        bash -c 'curl -fsSL https://get.docker.com | sh'
    fi
    capture_step 30 "engine_install_failed" 24 \
      "Enabling Docker service" "Docker service enabled" \
      systemctl enable --now docker
    ;;
  podman)
    if ! command -v podman >/dev/null 2>&1; then
      command -v apt-get >/dev/null 2>&1 ||
        fail "unsupported_os" 22 \
          "apt-get is required for automatic Podman installation."
      capture_step 300 "engine_install_failed" 24 \
        "Installing Podman and Compose support" \
        "Podman and its Compose provider installed" \
        bash -c 'apt-get update -qq &&
          DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman podman-compose'
    fi
    capture_step 20 "podman_inspection_failed" 29 \
      "Checking Podman Compose support" "Podman Compose provider is available" \
      podman compose version
    ;;
  *)
    fail "engine_install_failed" 23 "Unsupported container engine: $ENGINE."
    ;;
esac

phase "bootstrapping_access" 17 "Preparing the NMTK deployment account"
if getent group "$DEPLOY_GROUP" >/dev/null 2>&1; then
  terminal "✓ Deployment group already exists"
else
  capture_step 30 "deploy_account_failed" 25 \
    "Creating NMTK deployment group" "Deployment group created" \
    groupadd "$DEPLOY_GROUP"
fi
if id "$DEPLOY_USER" >/dev/null 2>&1; then
  terminal "✓ Deployment account already exists"
  capture_step 30 "deploy_account_failed" 25 \
    "Aligning NMTK deployment account" "Deployment account aligned" \
    usermod --gid "$DEPLOY_GROUP" "$DEPLOY_USER"
else
  capture_step 30 "deploy_account_failed" 25 \
    "Creating NMTK deployment account" "Deployment account created" \
    useradd --create-home --shell /bin/bash --gid "$DEPLOY_GROUP" "$DEPLOY_USER"
fi
capture_step 30 "deploy_account_failed" 25 \
  "Removing legacy deployment permissions" "Legacy sudo rule removed" \
  rm -f /etc/sudoers.d/nmtk-deploy
# The administrator account that ran setup needs to stay in the nmtk-deploy
# group so it can traverse /home/nmtk-deploy (drwxr-x---) and read the admin
# token later — without this, "Connect to existing server" silently fails and
# demands a reinstall they do not need.
# Under sudo, `id -un` is root — which already has access, so the grant
# did nothing for the account the operator actually logs in with.
ADMIN_USER="${SUDO_USER:-$(id -un)}"
if [ "$ADMIN_USER" != "$DEPLOY_USER" ] && [ -n "$ADMIN_USER" ]; then
  capture_step 30 "deploy_account_failed" 25 \
    "Granting administrator token access" \
    "Administrator account added to deployment group" \
    usermod -aG "$DEPLOY_GROUP" "$ADMIN_USER"
fi
if getent group docker >/dev/null 2>&1; then
  capture_step 30 "deploy_account_failed" 25 \
    "Granting deployment account Docker access" \
    "Deployment account can access Docker" \
    usermod -aG docker "$DEPLOY_USER"
fi

DEPLOY_HOME="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
DEPLOY_UID="$(id -u "$DEPLOY_USER")"
case "$DEPLOY_HOME" in
  /*) ;;
  *)
    terminal "✗ Deployment account has no valid home directory"
    fail "deploy_account_failed" 25 \
      "The deployment account has no valid home directory."
    ;;
esac
[ "$DEPLOY_HOME" != "/" ] || {
  terminal "✗ Deployment account cannot use the filesystem root as its home"
  fail "deploy_account_failed" 25 \
    "The deployment account cannot use the filesystem root as its home."
}
if [ ! -d "$DEPLOY_HOME" ]; then
  capture_step 30 "deploy_account_failed" 25 \
    "Creating NMTK deployment home" "Deployment home created" \
    install -d -m 750 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$DEPLOY_HOME"
else
  chmod 750 "$DEPLOY_HOME" 2>/dev/null || true
  if [ -d "$DEPLOY_HOME/.nmtk/deploy/credentials" ]; then
    chmod 750 "$DEPLOY_HOME/.nmtk" "$DEPLOY_HOME/.nmtk/deploy" "$DEPLOY_HOME/.nmtk/deploy/credentials" 2>/dev/null || true
    chmod 640 "$DEPLOY_HOME/.nmtk/deploy/credentials/admin-token" 2>/dev/null || true
  fi
fi
capture_step 30 "deploy_account_failed" 26 \
  "Preparing deployment credential workspace" \
  "Deployment credential workspace prepared" \
  mktemp -d /tmp/nmtk-deploy-key.XXXXXX
TEMPORARY_KEY_DIR="$STEP_OUTPUT"
TEMPORARY_KEY="$TEMPORARY_KEY_DIR/id_ed25519"
capture_step 30 "deploy_account_failed" 26 \
  "Generating a new deployment credential" "Deployment credential generated" \
  ssh-keygen -q -t ed25519 -N "" -f "$TEMPORARY_KEY"
capture_step 30 "deploy_account_failed" 26 \
  "Preparing deployment account SSH access" "Deployment SSH directory prepared" \
  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$DEPLOY_HOME/.ssh"
capture_step 30 "deploy_account_failed" 26 \
  "Installing the new deployment credential" "Deployment public key installed" \
  install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" \
  "$TEMPORARY_KEY.pub" "$DEPLOY_HOME/.ssh/authorized_keys"

if [ "$ENGINE" = "podman" ]; then
  capture_step 30 "deploy_account_failed" 27 \
    "Enabling persistent rootless Podman access" \
    "Deployment account lingering enabled" \
    loginctl enable-linger "$DEPLOY_USER"
  capture_step 30 "deploy_account_failed" 27 \
    "Starting the deployment account service manager" \
    "Deployment account service manager started" \
    systemctl start "user@$DEPLOY_UID.service"
  capture_step 30 "deploy_account_failed" 27 \
    "Preparing rootless Podman runtime" \
    "Rootless Podman runtime directory prepared" \
    install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" \
    "/run/user/$DEPLOY_UID"
  NMTK_SETUP_AUTOMATIC_RECOVERY=true \
  capture_step 30 "podman_api_start_failed" 27 \
    "Starting or repairing rootless Podman API" \
    "Rootless Podman API started" \
    runuser -u "$DEPLOY_USER" -- env \
      "HOME=$DEPLOY_HOME" "XDG_RUNTIME_DIR=/run/user/$DEPLOY_UID" \
      bash -c '
        socket="$XDG_RUNTIME_DIR/podman/podman.sock"
        remote_url="unix://$socket"
        # Non-interactive SSH sessions commonly have no user D-Bus even after
        # lingering is enabled. Persist the socket when systemd is available,
        # but never let that optional path block the detached Podman fallback.
        timeout --signal=TERM --kill-after=1s 5s \
          systemctl --user enable podman.socket >/dev/null 2>&1 || true
        timeout --signal=TERM --kill-after=1s 5s \
          systemctl --user start podman.socket >/dev/null 2>&1 || true
        for attempt in 1 2 3 4 5; do
          if [ -S "$socket" ] &&
             podman --remote --url "$remote_url" info --format \
               "version={{.Version.Version}} rootless={{.Host.Security.Rootless}} storage={{.Store.GraphRoot}}"; then
            exit 0
          fi
          sleep 0.4
        done

        timeout --signal=TERM --kill-after=1s 5s \
          systemctl --user stop podman.socket >/dev/null 2>&1 || true
        mkdir -p "$XDG_RUNTIME_DIR/podman"
        rm -f -- "$socket"
        command -v setsid >/dev/null 2>&1 || {
          printf "setsid is required to start the fallback Podman service\n" >&2
          exit 1
        }
        setsid -f podman system service --time=0 "$remote_url" \
          </dev/null >"$HOME/.nmtk-podman-service.log" 2>&1
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
          if [ -S "$socket" ] &&
             podman --remote --url "$remote_url" info --format \
               "version={{.Version.Version}} rootless={{.Host.Security.Rootless}} storage={{.Store.GraphRoot}}"; then
            exit 0
          fi
          sleep 0.5
        done
        printf "The rootless Podman API did not become ready after automatic recovery.\n" >&2
        exit 1'
  capture_step 20 "podman_api_start_failed" 27 \
    "Verifying rootless Podman API" "Rootless Podman API is ready" \
    runuser -u "$DEPLOY_USER" -- env \
      "HOME=$DEPLOY_HOME" "XDG_RUNTIME_DIR=/run/user/$DEPLOY_UID" \
      bash -c 'socket="$XDG_RUNTIME_DIR/podman/podman.sock"
      for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if [ -S "$socket" ] &&
           podman --remote --url "unix://$socket" info --format \
             "version={{.Version.Version}} rootless={{.Host.Security.Rootless}} storage={{.Store.GraphRoot}}"; then
          exit 0
        fi
        sleep 1
      done
      exit 1'
fi

step_marker start 40 false "Finalizing secure deployment handoff"
set +e
PRIVATE_KEY_B64="$(
  timeout --signal=TERM --kill-after=1s 5s \
    base64 <"$TEMPORARY_KEY" | tr -d '\n'
)"
key_encode_exit="$?"
set -e
[ "$key_encode_exit" -eq 0 ] ||
  fail "deploy_account_failed" 26 \
    "The generated deployment credential could not be secured for handoff."

for runtime_entry in "${TEMP_RUNTIME_DIRS[@]-}"; do
  [ -n "$runtime_entry" ] || continue
  runtime_user="${runtime_entry%%:*}"
  runtime_dir="${runtime_entry#*:}"
  [ -n "$runtime_dir" ] || continue
  case "$runtime_dir" in
    /tmp/nmtk-podman-runtime.*)
      set +e
      timeout --signal=TERM --kill-after=1s 10s rm -rf -- "$runtime_dir"
      cleanup_exit="$?"
      set -e
      [ "$cleanup_exit" -eq 0 ] ||
        fail "podman_inspection_failed" 29 \
          "The temporary Podman runtime for user $runtime_user could not be removed."
      ;;
  esac
done
TEMP_RUNTIME_DIRS=()

set +e
timeout --signal=TERM --kill-after=1s 10s \
  rm -rf -- "$TEMPORARY_KEY_DIR"
key_cleanup_exit="$?"
set -e
[ "$key_cleanup_exit" -eq 0 ] ||
  fail "deploy_account_failed" 26 \
    "The temporary deployment credential directory could not be removed."
TEMPORARY_KEY_DIR=""

terminal "✓ Server preparation completed"
printf 'NMTK_DEPLOY_PRIVATE_KEY_B64=%s\n' "$PRIVATE_KEY_B64"
unset PRIVATE_KEY_B64
step_marker finish 40 false "Finalizing secure deployment handoff"
'''
      .replaceAll('__ENGINE__', containerEngine)
      .replaceAll('__FACTORY_RESET__', resetFlag);
}
