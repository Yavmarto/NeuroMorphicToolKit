# monitoring

**Nothing here is running.** This directory holds configuration files for an observability stack that is not referenced by any Docker Compose file in this repository. There is no `monitoring` profile, no `monitoring-net` network, and no Prometheus, Grafana, Loki, Promtail, or Alertmanager service defined anywhere. Verify with:

```bash
grep -rn "prometheus\|grafana\|loki\|promtail\|alertmanager" docker-compose*.yml
```

which returns nothing.

## What exists as files today

- `prometheus/prometheus.yml` — scrape config, with `rule_files: ["alert_rules.yml"]`
- `prometheus/alert_rules.yml` — availability, error-rate, and latency rules
- `alertmanager/alertmanager.yml` — routes to a `null-receiver`; no notifier is configured
- `loki/loki-config.yml` — log store config
- `promtail/promtail-config.yml` — Docker log discovery with a name-based keep filter
- `grafana/provisioning/datasources/ds.yml` — Prometheus and Loki datasources
- `grafana/provisioning/dashboards/dashboards.yml` — dashboard provider
- `grafana/dashboards/nmtk-overview.json` — the `NMTK Overview` dashboard
- Three design notes in [`issues - future/`](./issues%20-%20future)

## What is missing before this can run

- **No compose services and no profile.** The stack would need to be added to `docker-compose.yml` first.
- **Nothing to scrape.** The only uncommented scrape target is `suite_api:9000`, which exposes no `/metrics` route, so the error-rate and latency rules cannot fire. The four worker targets are commented out and are not enabled by any compose profile — they need a manual edit. `neurocnl`'s backend does expose `/metrics`, but it is not a compose service and not a scrape target.
- **Promtail's filter excludes the primary backend.** Its keep-regex matches only container names containing `neurocnl`, `neurochip`, `neurobench`, `neurosense`, or `neurohub`, which drops `suite_api`, `launcher-control`, `jupyter-server`, `lava-backend`, and `snn-mlir-compiler`.
- **Alertmanager delivers nowhere** until a real receiver is configured.

---

## Future / Planned

*Everything below describes an intended design, not current behaviour.*

### Prometheus
Would scrape `suite_api` and, once their metrics endpoints exist and the targets are uncommented, the physics, Neurosense, Neurobench, and Neurochip workers. Alert rules for overall availability, error rate, and request latency are already written.

### Alertmanager
Would route firing alerts to a notifier. The routing tree exists; only the `null-receiver` is defined.

### Loki and Promtail
Promtail would tail Docker container logs and ship them to Loki, giving log search alongside metrics.

### Grafana
Would provision the Prometheus and Loki datasources and load the `NMTK Overview` dashboard, whose panels cover overall availability, throughput, p95 latency, and aggregated logs.

### Intended endpoints, once wired
Grafana `:3000`, Prometheus `:9090`, Alertmanager `:9093`, Loki `:3100`.

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](../LICENSE).
