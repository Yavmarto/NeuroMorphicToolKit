# monitoring

`monitoring` is the observability stack for the NMTK backend services.

## What It Should Do

This folder is already wired into the root [`docker-compose.yml`](../docker-compose.yml), so its intended role is clear:

- scrape service health and request metrics
- collect logs from the running module containers
- visualize suite health in Grafana
- raise alerts when services go down or become unhealthy

In other words, this is the shared monitoring plane for the NMTK microservice suite.

## How The Pieces Fit Together

### Prometheus

[`prometheus/prometheus.yml`](./prometheus/prometheus.yml) scrapes:

- `suite_api`
- optional worker targets when those profiles are enabled:
  `neurocnl-physics-worker`, `neurosense-hw-worker`, `neurobench-runner-worker`,
  `neurochip-hw-worker`

It also loads alert rules from [`prometheus/alert_rules.yml`](./prometheus/alert_rules.yml).

### Alertmanager

[`alertmanager/alertmanager.yml`](./alertmanager/alertmanager.yml) groups alerts, but currently sends them to a `null-receiver`. That means the alert pipeline exists structurally, but notification delivery has not been configured yet.

### Loki + Promtail

- [`promtail/promtail-config.yml`](./promtail/promtail-config.yml) watches Docker containers and keeps only the active NMTK service logs.
- [`loki/loki-config.yml`](./loki/loki-config.yml) stores and serves those logs for querying.

### Grafana

Grafana is provisioned with:

- a Prometheus datasource
- a Loki datasource
- a preloaded dashboard at [`grafana/dashboards/nmtk-overview.json`](./grafana/dashboards/nmtk-overview.json)

So the intended experience is a suite dashboard that combines metrics and logs in one place.

## Why This Fits The Rest Of NMTK

Several modules already expose health or metrics endpoints, and `neurocnl` explicitly includes Prometheus middleware. The root compose stack also places every service on a `monitoring-net`, which strongly suggests the long-term production model is:

- each module exposes health and metrics
- the root stack scrapes them centrally
- operators use Grafana and alerts to see whether the suite is healthy

This matches the repository's production and CI goals much better than module-by-module manual checking.

## Current State

This folder is much further along than `neurocli`.

What already exists:

- Prometheus config
- alert rules
- Loki config
- Promtail config
- Grafana datasource/dashboard provisioning
- root Docker Compose integration

What still looks unfinished:

- Alertmanager notifications are still a no-op
- only modules with real metrics endpoints will provide useful Prometheus data
- dashboard coverage likely needs to expand as more modules expose metrics consistently

## Typical Usage

Start the observability stack with the monitoring profile:

```bash
docker compose --profile monitoring up -d
```

Once running, the intended endpoints are:

- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
- Alertmanager: `http://localhost:9093`
- Loki: `http://localhost:3100`

## Practical Mental Model

If `Neurohub` is the product-level orchestrator, `monitoring` is the operator-level observability layer underneath it.
