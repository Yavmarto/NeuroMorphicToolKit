#!/usr/bin/env bash
# Verify Prometheus sees core NMTK scrape targets as UP.
# Usage: scripts/verify_monitoring_targets.sh [prometheus_url]
set -euo pipefail

PROM="${1:-http://127.0.0.1:9090}"
export TARGETS_JSON
TARGETS_JSON="$(curl -fsS "${PROM}/api/v1/targets")"

python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["TARGETS_JSON"])
active = payload.get("data", {}).get("activeTargets", [])
required = {
    "suite_api",
    "launcher-control",
    "neurobench-runner-worker",
    "neurochip-hw-worker",
    "neurocnl-physics-worker",
    "lava-backend",
    "brian2-backend",
    "snn-mlir-compiler",
    "jupyter-server",
}

by_instance = {}
for target in active:
    labels = target.get("labels", {})
    instance = labels.get("instance", "")
    by_instance[instance] = target.get("health", "unknown")

missing = sorted(required - set(by_instance))
down = sorted(instance for instance in required if by_instance.get(instance) != "up")

if missing:
    print("Missing scrape targets:", ", ".join(missing))
if down:
    print("Targets not UP:", ", ".join(f"{name}={by_instance.get(name, 'missing')}" for name in down))

if missing or down:
    raise SystemExit(1)

print(f"All {len(required)} core targets UP")
for name in sorted(required):
    print(f"  OK  {name}")
PY
