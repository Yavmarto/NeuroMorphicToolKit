#!/bin/sh
# NMTK Alertmanager entrypoint.
#
# Alertmanager cannot expand environment variables in its config file, so this
# wrapper reads the Slack webhook secret from the environment, writes it to the
# file that alertmanager.yml references with `api_url_file`, and then starts
# Alertmanager with the expected flags.
#
# Required environment:
#   SLACK_WEBHOOK_URL   Slack incoming-webhook URL for #nmtk-alerts.
#
# Optional environment:
#   ALERTMANAGER_CONFIG_FILE    default /etc/alertmanager/alertmanager.yml
#   ALERTMANAGER_STORAGE_PATH   default /alertmanager
#   ALERTMANAGER_SECRET_DIR     default /etc/alertmanager/secrets
set -eu

config_file="${ALERTMANAGER_CONFIG_FILE:-/etc/alertmanager/alertmanager.yml}"
storage_path="${ALERTMANAGER_STORAGE_PATH:-/alertmanager}"
secret_dir="${ALERTMANAGER_SECRET_DIR:-/etc/alertmanager/secrets}"
secret_file="${secret_dir}/slack_webhook_url"

if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "[alertmanager] SLACK_WEBHOOK_URL is not set." >&2
  echo "[alertmanager] Set it to the Slack incoming-webhook URL for #nmtk-alerts." >&2
  echo "[alertmanager] For a start-only local smoke test, any URL is accepted, for example:" >&2
  echo "[alertmanager]   SLACK_WEBHOOK_URL=http://127.0.0.1:9093/slack" >&2
  exit 1
fi

if [ "$SLACK_WEBHOOK_URL" = "http://127.0.0.1:9093/slack" ]; then
  echo "[alertmanager] WARNING: SLACK_WEBHOOK_URL is the local no-op default." >&2
  echo "[alertmanager] Alerts will fire but will not reach #nmtk-alerts." >&2
fi

mkdir -p "$secret_dir"
if ! printf '%s' "$SLACK_WEBHOOK_URL" > "$secret_file" 2>/dev/null; then
  echo "[alertmanager] Cannot write secret file $secret_file." >&2
  echo "[alertmanager] Do not mount it read-only; this entrypoint creates it." >&2
  exit 1
fi
chmod 600 "$secret_file" 2>/dev/null || true

exec /bin/alertmanager --config.file="$config_file" --storage.path="$storage_path"
