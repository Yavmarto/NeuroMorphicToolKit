#!/usr/bin/env bash
# scripts/verify_alertmanager_routing.sh
#
# End-to-end check that Alertmanager delivers a synthetic critical alert and a
# synthetic warning alert to the Slack receiver defined in
# monitoring/alertmanager/alertmanager.yml.
#
# It runs Alertmanager with the real config and the real entrypoint, but points
# the Slack webhook at a local throwaway HTTP sink instead of Slack. A passing
# run proves routing and delivery; it does not need a real Slack secret.
#
# Usage: bash scripts/verify_alertmanager_routing.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AM_DIR="$ROOT_DIR/monitoring/alertmanager"
CONFIG_FILE="$AM_DIR/alertmanager.yml"
ENTRYPOINT_FILE="$AM_DIR/entrypoint.sh"

ALERTMANAGER_IMAGE="${ALERTMANAGER_IMAGE:-prom/alertmanager:v0.28.1}"
SINK_IMAGE="${ALERTMANAGER_SINK_IMAGE:-python:3.12-alpine}"
NETWORK="${ALERTMANAGER_VERIFY_NETWORK:-nmtk-am-verify-net}"
SINK_CONTAINER="${ALERTMANAGER_VERIFY_SINK:-nmtk-am-verify-sink}"
AM_CONTAINER="${ALERTMANAGER_VERIFY_AM:-nmtk-am-verify-alertmanager}"
SINK_PORT=8080
TIMEOUT_SECONDS="${ALERTMANAGER_VERIFY_TIMEOUT:-120}"

TMP_DIR="$(mktemp -d)"
SINK_SCRIPT="$TMP_DIR/sink.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cleanup() {
  docker rm -f "$AM_CONTAINER" "$SINK_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 || fail "docker is not installed"
docker info >/dev/null 2>&1 || fail "docker daemon is not reachable"

[ -f "$CONFIG_FILE" ] || fail "missing $CONFIG_FILE"
[ -f "$ENTRYPOINT_FILE" ] || fail "missing $ENTRYPOINT_FILE"

if grep -q "null-receiver" "$CONFIG_FILE"; then
  fail "config still references null-receiver"
fi

cat > "$SINK_SCRIPT" <<'PY'
import http.server, json, sys

PORT = int(sys.argv[1])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", "replace")
        print("ALERTMANAGER_POST " + json.dumps({"path": self.path, "body": body}), flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, *args):
        pass


http.server.HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
PY

echo "==> Creating network and Slack sink"
docker network create "$NETWORK" >/dev/null
docker run -d --name "$SINK_CONTAINER" --network "$NETWORK" \
  -v "$SINK_SCRIPT:/sink.py:ro" "$SINK_IMAGE" python /sink.py "$SINK_PORT" >/dev/null

echo "==> Starting Alertmanager with the real config and entrypoint"
docker run -d --name "$AM_CONTAINER" --network "$NETWORK" \
  -e "SLACK_WEBHOOK_URL=http://${SINK_CONTAINER}:${SINK_PORT}/slack" \
  -v "$CONFIG_FILE:/etc/alertmanager/alertmanager.yml:ro" \
  -v "$ENTRYPOINT_FILE:/entrypoint.sh:ro" \
  --entrypoint /bin/sh \
  "$ALERTMANAGER_IMAGE" /entrypoint.sh >/dev/null

echo "==> Waiting for Alertmanager to become healthy"
healthy=false
for _ in $(seq 1 "$TIMEOUT_SECONDS"); do
  if docker exec "$AM_CONTAINER" wget -qO- http://localhost:9093/-/healthy >/dev/null 2>&1; then
    healthy=true
    break
  fi
  sleep 1
done
if [ "$healthy" != "true" ]; then
  docker logs "$AM_CONTAINER" >&2 || true
  fail "Alertmanager did not become healthy within ${TIMEOUT_SECONDS}s"
fi

echo "==> Firing a synthetic critical alert and a synthetic warning alert"
docker exec "$AM_CONTAINER" amtool --alertmanager.url=http://localhost:9093 alert add \
  ServiceDown severity=critical instance=suite_api job=nmtk-services \
  --annotation='summary="suite_api down"' --annotation='description="down for more than 1 minute"' >/dev/null
docker exec "$AM_CONTAINER" amtool --alertmanager.url=http://localhost:9093 alert add \
  HighErrorRate severity=warning instance=suite_api job=nmtk-services \
  --annotation='summary="5xx error rate above 5 percent"' --annotation='description="more than 5 percent 5xx responses"' >/dev/null

echo "==> Waiting for delivery to the receiver"
delivered=""
for _ in $(seq 1 "$TIMEOUT_SECONDS"); do
  delivered="$(docker logs "$SINK_CONTAINER" 2>&1 | grep 'ALERTMANAGER_POST' || true)"
  if echo "$delivered" | grep -q '\[CRITICAL\] ServiceDown' \
    && echo "$delivered" | grep -q '\[WARNING\] HighErrorRate'; then
    break
  fi
  sleep 1
done

echo "$delivered" | grep -q '\[CRITICAL\] ServiceDown' \
  || fail "critical alert was not delivered to the Slack receiver"
echo "$delivered" | grep -q 'receiver=nmtk-critical' \
  || fail "critical alert was not routed through the nmtk-critical receiver"
echo "$delivered" | grep -q '\[WARNING\] HighErrorRate' \
  || fail "warning alert was not delivered to the Slack receiver"
echo "$delivered" | grep -q 'receiver=nmtk-warning' \
  || fail "warning alert was not routed through the nmtk-warning receiver"
echo "$delivered" | grep -q '#nmtk-alerts' \
  || fail "alerts were not addressed to #nmtk-alerts"

echo "PASS: critical and warning alerts were routed and delivered to the Slack receiver."
