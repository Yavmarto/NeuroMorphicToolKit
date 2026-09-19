# monitoring

Observability configs for the NMTK Docker stack. The stack is opt-in: it is
defined in `docker-compose.yml` behind the `monitoring` profile, so a normal
`docker compose up -d` and an end-user deployment never start it.

## Deployment model

**Dev and CI only** — decided by the CTO on 2026-09-17. The stack does not run
in production and no production host is given access to it. Two things enforce
this: the `monitoring` profile is off by default, and the end-user deployment
bundle (`nmtk/neuro_toolkit/assets/deployment/`) never enables it. CI proves the
profile still starts through the `Monitoring Smoke` workflow
(`.github/workflows/monitoring-smoke.yml`). It stays out of the required
`ci-passed` gate, because it pulls five images and boots Grafana.

Enable it with:

```bash
docker compose --profile monitoring up -d   # or: make monitoring-up
make monitoring-urls                        # print the local endpoints
```

`make` targets: `monitoring-up`, `monitoring-down`, `monitoring-logs`,
`monitoring-urls`, `monitoring-smoke`.

Smoke test (starts only the observability services on throwaway high ports,
checks readiness and Grafana provisioning, then tears down):

```bash
make monitoring-smoke        # or: bash scripts/monitoring_smoke.sh
```

After the stack is up, verify the suite scrape targets are UP:

```bash
bash scripts/verify_monitoring_targets.sh
```

## Ports and exposure

Every monitoring port binds to `${MONITORING_BIND:-127.0.0.1}` and is therefore
reachable only from the host itself by default. Set `MONITORING_BIND=0.0.0.0`
only on a host you trust on the local network. Override an individual port with
`GRAFANA_PORT`, `PROMETHEUS_PORT`, `ALERTMANAGER_PORT`, `LOKI_PORT`,
`PROMTAIL_PORT`. Set `GRAFANA_ADMIN_PASSWORD` before first start; the default
`admin` password is for local use only.

## Contract

See [`METRICS_CONTRACT.md`](./METRICS_CONTRACT.md) for the required `/metrics` path,
metric names (`http_requests_total`, `http_request_duration_seconds`), and scrape
targets.

Shared instrumentation lives in [`nmtk/metrics_core.py`](../nmtk/metrics_core.py)
and [`nmtk/http_metrics.py`](../nmtk/http_metrics.py) (FastAPI services only).

## Layout

- `prometheus/prometheus.yml` — scrape config for all suite HTTP services
- `prometheus/alert_rules.yml` — availability, error-rate, and latency rules
- `alertmanager/alertmanager.yml` — routes critical and warning alerts to Slack (#nmtk-alerts); see [`alertmanager/README.md`](./alertmanager/README.md)
- `loki/loki-config.yml` — log store config
- `promtail/promtail-config.yml` — Docker log discovery with suite container keep-filter
- `grafana/provisioning/` — Prometheus and Loki datasources
- `grafana/dashboards/nmtk-overview.json` — availability, throughput, p95 latency, logs

## Endpoints (monitoring profile)

Grafana `:3000`, Prometheus `:9090`, Alertmanager `:9093`, Loki `:3100`,
Promtail `:9080` — all bound to `127.0.0.1` unless `MONITORING_BIND` is changed.

## Operator workflow: checking suite health

1. Start the stack: `make monitoring-up`.
2. Open Grafana at the printed URL (`http://127.0.0.1:3000` by default) and log
   in. The `NMTK Overview` dashboard is loaded automatically.
3. Read the dashboard. **Overall Availability** is `sum(up) / count(up)` across
   all scrape targets; below 1 means a target is down. **Throughput (RPS)** and
   **P95 Latency** cover request volume and tail latency. **Aggregated Logs**
   shows recent suite container logs from Loki.
4. Confirm scraping: `bash scripts/verify_monitoring_targets.sh`, or Prometheus
   → Status → Targets at `http://127.0.0.1:9090`.
5. Search logs: Grafana → Explore → Loki, for example `{container="suite_api"}`.
6. Check firing alerts: Prometheus → Alerts, and the Alertmanager UI at
   `http://127.0.0.1:9093`.
7. Stop the stack: `make monitoring-down`. Metrics, logs, and Grafana state live
   in named volumes; `docker compose --profile monitoring down -v` deletes them.

## Alerting

Alertmanager delivers to the Slack channel **#nmtk-alerts**. Set
`SLACK_WEBHOOK_URL` in `.env` before starting the profile; without it alerts
fire but are not delivered. Severity routing, secret handling, and the
end-to-end verification script are in
[`alertmanager/README.md`](./alertmanager/README.md).

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](../LICENSE).
