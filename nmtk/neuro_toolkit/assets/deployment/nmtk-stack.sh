#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-start}"
ENGINE="${2:-podman}"
DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_ARGS=(
  compose --project-name nmtk
  -f "$DEPLOY_DIR/docker-compose.yml"
  -f "$DEPLOY_DIR/docker-compose.prod.yml"
  -f "$DEPLOY_DIR/docker-compose.remote.yml"
)

start_stack() {
  "$ENGINE" "${COMPOSE_ARGS[@]}" up -d --no-build --remove-orphans
}

install_podman_boot_service() {
  [ "$ENGINE" = "podman" ] || return 0
  command -v systemctl >/dev/null 2>&1 || {
    printf '%s\n' 'Rootless Podman boot recovery requires systemd.' >&2
    return 1
  }

  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export XDG_RUNTIME_DIR="$runtime_dir"
  if [ -S "$runtime_dir/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
  fi

  unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$unit_dir"
  unit_path="$unit_dir/nmtk-stack.service"
  quoted_script=$(printf '%q' "$DEPLOY_DIR/nmtk-stack.sh")
  cat >"$unit_path" <<EOF
[Unit]
Description=NMTK backend stack
Wants=network-online.target podman.socket
After=network-online.target podman.socket

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$DEPLOY_DIR
ExecStart=/bin/bash $quoted_script start podman

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable nmtk-stack.service
  systemctl --user is-enabled --quiet nmtk-stack.service
}

case "$ACTION" in
  install)
    install_podman_boot_service
    ;;
  start)
    start_stack
    ;;
  check)
    if [ "$ENGINE" = "podman" ]; then
      systemctl --user is-enabled --quiet nmtk-stack.service
    fi
    "$ENGINE" "${COMPOSE_ARGS[@]}" ps --status running
    ;;
  *)
    printf 'Unknown NMTK stack action: %s\n' "$ACTION" >&2
    exit 2
    ;;
esac
