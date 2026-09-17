# neurocnl Backend — Operator Guide

## Job Lifecycle

```
queued  ──▶  running  ──▶  complete
                │
                └──▶  failed  (error / timeout / server_restart)
```

- **Timeout**: 60 seconds default (enforced via `asyncio.wait_for`).
- **Cleanup**: Background task runs every **1 hour**, deleting jobs with
  `updated_at` older than **24 hours**.
- **Persistence**: SQLite (`jobs.db`). Jobs survive restarts.

### Startup Recovery

On boot, any job still in `running` state is marked `failed` with error
`server_restart: job was running when server shut down`.

Watch for `neurocnl_job_completions_total{status="failed"}` spikes after
restarts.

### Graceful Shutdown

The server waits up to **10 seconds** for active tasks to finish. Remaining
tasks are cancelled and logged.

## Prometheus Metrics

### HTTP (all routes, via middleware)

| Metric | Type | Labels |
|--------|------|--------|
| `http_requests_total` | Counter | `method`, `endpoint`, `status_code` |
| `http_request_duration_seconds` | Histogram | `method`, `endpoint` |

### Jobs

| Metric | Type | Labels |
|--------|------|--------|
| `neurocnl_job_queue_depth` | Gauge | — |
| `neurocnl_job_active_tasks` | Gauge | — |
| `neurocnl_job_completions_total` | Counter | `status` (`complete` / `failed` / `timeout`) |
| `neurocnl_job_duration_seconds` | Histogram | — |

### Deploy

| Metric | Type | Labels |
|--------|------|--------|
| `neurocnl_deploy_verdicts_total` | Counter | `target` (`teensy` / `pynq` / `akida`), `verdict` |

### Endpoint

`GET /metrics` — Prometheus text format.

## Structured Logging

**Framework**: structlog

**Format**: Set `LOG_FORMAT=json` for production (default is human-readable
console format).

**Key fields** in every log line:

| Field | Source |
|-------|--------|
| `request_id` | Bound by `RequestIDMiddleware` via `structlog.contextvars` |
| `job_id` | Bound when a background job starts executing |
| `event` | structlog event name (e.g. `job_failed`, `teensy_deploy_rejected`) |
| `timestamp` | ISO 8601 |

## Correlating a Request to a Job Failure

1. Note the `X-Request-ID` response header from the original HTTP request.
2. Search logs for that `request_id` to find the associated `job_id`.
3. Search logs for that `job_id` to find the failure details.

Example (JSON log format):

```json
{"request_id": "abc-123", "job_id": "def-456", "event": "job_failed", ...}
```

The `request_id` is also stored in the jobs database and returned in the
`GET /api/jobs/{job_id}` response.

## Known Limitations

- Cleanup deletes by `updated_at`, not `created_at`. A job stuck in `queued`
  (never transitioned to `running`) will survive cleanup until its
  `updated_at` exceeds the 24h TTL.
- No job cancellation API. Jobs run to completion, timeout, or server restart.
- Export and deploy endpoints are synchronous (no background jobs). They
  complete within the HTTP request timeout.
