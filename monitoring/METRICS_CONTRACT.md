# NMTK HTTP metrics contract

Every HTTP service in the suite Docker stack exposes Prometheus metrics at **`GET /metrics`**
on its primary listen port. The endpoint is unauthenticated (same trust boundary as
`/health` — reachable only on `backend-net` or the operator's host port map).

## Required series (all HTTP services)

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `http_requests_total` | Counter | `method`, `endpoint`, `status_code` | Request volume and error rate |
| `http_request_duration_seconds` | Histogram | `method`, `endpoint` | Latency (p50/p95 via `histogram_quantile`) |

`endpoint` must use the FastAPI route template when available (e.g. `/api/jobs/{job_id}`),
not the raw URL path, so cardinality stays bounded.

## Error rate

Prometheus alert and dashboard queries treat HTTP 5xx as errors:

```promql
sum(rate(http_requests_total{status_code=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
```

## Service scrape targets (compose network)

| Service | Target | Notes |
|---------|--------|-------|
| `suite_api` | `suite_api:9000` | Unified suite API (includes neurocnl/neurosim routes) |
| `launcher-control` | `launcher-control:8091` | Stdlib HTTP control plane |
| `neurobench-runner-worker` | `neurobench-runner-worker:8003` | Always on in default stack |
| `neurochip-hw-worker` | `neurochip-hw-worker:8002` | Always on in default stack |
| `neurosense-hw-worker` | `neurosense-hw-worker:8004` | `neurosense` profile only |
| `neurocnl-physics-worker` | `neurocnl-physics-worker:8006` | MuJoCo worker |
| `lava-backend` | `lava-backend:8012` | Lava runtime |
| `brian2-backend` | `brian2-backend:8013` | Brian2 runtime |
| `snn-mlir-compiler` | `snn-mlir-compiler:8007` | MLIR compiler worker |
| `jupyter-server` | `jupyter-server:8008` | Jupyter Server + NMTK extensions |

Implementation lives in [`nmtk/http_metrics.py`](../nmtk/http_metrics.py) for FastAPI
services and launcher-control; Jupyter uses a small Server extension that hooks Tornado's
`log_function`.

## Optional module-specific metrics

Services may export additional counters/histograms (job queue depth, hardware SDK
availability, etc.). Those are module-owned and not required for suite-level availability,
throughput, or latency alerts.
