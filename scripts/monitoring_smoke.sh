#!/usr/bin/env bash
#
# scripts/monitoring_smoke.sh — smoke test for the opt-in `monitoring` profile.
#
# Starts only the observability services under a throwaway Compose project on
# high host ports, verifies that Prometheus, Alertmanager, Loki, Promtail and
# Grafana come up, and verifies that Grafana provisioned its datasources and the
# NMTK Overview dashboard with no manual steps. Then tears everything down.
#
# It does not touch the default backend stack: it starts just the five
# monitoring services, so it is safe to run alongside a running dev stack.
#
# Usage:
#   bash scripts/monitoring_smoke.sh          # start, verify, tear down
#   MONITORING_SMOKE_KEEP=1 bash scripts/monitoring_smoke.sh   # keep containers
#   make monitoring-smoke
#
# Environment overrides:
#   MONITORING_SMOKE_PROJECT                default nmtk-monitoring-smoke
#   MONITORING_SMOKE_GRAFANA_PORT           default 13000
#   MONITORING_SMOKE_PROMETHEUS_PORT        default 19090
#   MONITORING_SMOKE_ALERTMANAGER_PORT      default 19093
#   MONITORING_SMOKE_LOKI_PORT              default 13100
#   MONITORING_SMOKE_PROMTAIL_PORT          default 19080
#   MONITORING_SMOKE_TIMEOUT                seconds to wait per service, default 180
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${MONITORING_SMOKE_PROJECT:-nmtk-monitoring-smoke}"
export MONITORING_BIND=127.0.0.1
export GRAFANA_PORT="${MONITORING_SMOKE_GRAFANA_PORT:-13000}"
export PROMETHEUS_PORT="${MONITORING_SMOKE_PROMETHEUS_PORT:-19090}"
export ALERTMANAGER_PORT="${MONITORING_SMOKE_ALERTMANAGER_PORT:-19093}"
export LOKI_PORT="${MONITORING_SMOKE_LOKI_PORT:-13100}"
export PROMTAIL_PORT="${MONITORING_SMOKE_PROMTAIL_PORT:-19080}"
GRAFANA_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-admin}"
export GRAFANA_ADMIN_USER="$GRAFANA_USER" GRAFANA_ADMIN_PASSWORD="$GRAFANA_PASS"
TIMEOUT="${MONITORING_SMOKE_TIMEOUT:-180}"

SERVICES=(prometheus alertmanager loki grafana promtail)
COMPOSE=(docker compose -p "$PROJECT" --profile monitoring)

PASS=0
FAIL=0
ok()   { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

cleanup() {
  if [ "${MONITORING_SMOKE_KEEP:-0}" = "1" ]; then
    echo "==> MONITORING_SMOKE_KEEP=1: leaving project '$PROJECT' running"
    return
  fi
  echo "==> Tearing down project '$PROJECT'"
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 || { echo "docker is not installed" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "docker daemon is not reachable" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for JSON assertions" >&2; exit 2; }

echo "==> Validating the base compose file with the monitoring profile"
"${COMPOSE[@]}" config --quiet

# Start without `--wait`: compose's fail-fast on an unhealthy healthcheck makes
# the test flaky under load. The readiness polling below is the gate instead.
echo "==> Starting monitoring services (project '$PROJECT')"
"${COMPOSE[@]}" up -d "${SERVICES[@]}"

PROM_URL="http://127.0.0.1:${PROMETHEUS_PORT}"
AM_URL="http://127.0.0.1:${ALERTMANAGER_PORT}"
LOKI_URL="http://127.0.0.1:${LOKI_PORT}"
PROMTAIL_URL="http://127.0.0.1:${PROMTAIL_PORT}"
GRAFANA_URL="http://127.0.0.1:${GRAFANA_PORT}"

# Poll an endpoint until it answers with a 2xx. Grafana gets its own, larger
# budget: a first boot on a fresh volume runs ~600 migrations.
wait_ready() {
  local name="$1" url="$2" limit="${3:-$TIMEOUT}"
  local deadline=$((SECONDS + limit))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      ok "$name is ready ($url)"
      return 0
    fi
    sleep 2
  done
  bad "$name did not become ready within ${limit}s ($url)"
  return 1
}

echo "==> Checking service readiness"
wait_ready "Prometheus"   "$PROM_URL/-/ready"       || true
wait_ready "Alertmanager" "$AM_URL/-/healthy"       || true
wait_ready "Loki"         "$LOKI_URL/ready"         || true
wait_ready "Promtail"     "$PROMTAIL_URL/ready"     || true
wait_ready "Grafana"      "$GRAFANA_URL/api/health" "${GRAFANA_TIMEOUT:-420}" || true

echo "==> Checking Prometheus loaded its rule files and scrape config"
if curl -fsS "$PROM_URL/api/v1/status/config" 2>/dev/null | grep -q "alert_rules.yml"; then
  ok "Prometheus rule_files includes alert_rules.yml"
else
  bad "Prometheus config does not reference alert_rules.yml"
fi

echo "==> Checking Grafana provisioning (datasources + dashboard)"
DS_JSON="$(curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/datasources" 2>/dev/null || true)"
if printf '%s' "$DS_JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
by_name = {d.get("name"): d for d in data}
prom = by_name.get("Prometheus")
loki = by_name.get("Loki")
assert prom and prom.get("type") == "prometheus", "Prometheus datasource missing or wrong type"
assert prom.get("isDefault") is True, "Prometheus datasource is not the default"
assert loki and loki.get("type") == "loki", "Loki datasource missing or wrong type"
' 2>/dev/null; then
  ok "Grafana has default Prometheus + Loki datasources"
else
  bad "Grafana datasources were not provisioned as expected"
fi

if curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/dashboards/uid/nmtk-overview" 2>/dev/null \
  | python3 -c '
import json, sys
payload = json.load(sys.stdin)
dashboard = payload.get("dashboard") or {}
assert dashboard.get("title") == "NMTK Overview", "unexpected dashboard title"
assert dashboard.get("panels"), "dashboard has no panels"
' 2>/dev/null; then
  ok "Grafana provisioned the 'NMTK Overview' dashboard"
else
  bad "Grafana did not provision the 'NMTK Overview' dashboard"
fi

echo
echo "==> Smoke test summary: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -ne 0 ]; then
  echo "==> Container status:"
  "${COMPOSE[@]}" ps || true
  echo "==> Recent logs:"
  "${COMPOSE[@]}" logs --tail=40 || true
  exit 1
fi
echo "Monitoring stack smoke test passed."
