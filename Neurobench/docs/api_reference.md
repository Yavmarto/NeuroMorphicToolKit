# NeuroBench API Reference

This page documents the human-facing NeuroBench HTTP API. The live OpenAPI
schema at `/openapi.json` is authoritative for exact request and response
models.

Default base URL: `http://127.0.0.1:8003`

Live docs:

- Swagger UI: `http://127.0.0.1:8003/docs`
- OpenAPI JSON: `http://127.0.0.1:8003/openapi.json`
- Health: `http://127.0.0.1:8003/health`

## Authentication

API-key authentication is optional. When `NB_AUTH_ENABLED=true`, router
endpoints require:

```http
X-API-Key: <NB_API_KEY>
```

`/health`, `/docs`, and `/openapi.json` are public.

## Operational Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Service health check. |
| `GET` | `/docs` | FastAPI Swagger UI. |
| `GET` | `/openapi.json` | Canonical generated OpenAPI schema. |

## Benchmark Definitions

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurobench/benchmarks` | List built-in and custom benchmark definitions. |
| `GET` | `/api/neurobench/benchmarks/{benchmark_id}` | Fetch one benchmark definition. |
| `POST` | `/api/neurobench/benchmarks` | Create a custom benchmark definition. |

## Benchmark Execution

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurobench/run` | Queue or run a benchmark execution. |
| `GET` | `/api/neurobench/run/{job_id}` | Poll benchmark job status. |
| `GET` | `/api/neurobench/run/{job_id}/result` | Fetch a completed benchmark result. |
| `DELETE` | `/api/neurobench/run/{job_id}` | Cancel or delete a benchmark job. |

Example run request:

```json
{
  "benchmark_id": "reaction_latency",
  "network_path": "examples/reflex.json",
  "params": {},
  "seed": 1
}
```

## Comparison and Regression

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurobench/compare/{baseline_ids}/{current_ids}` | Diff selected baseline and current result ids. |
| `GET` | `/api/neurobench/compare/export` | Export comparison output. |
| `POST` | `/api/neurobench/compare/targets` | Compare results across hardware or simulation targets. |
| `POST` | `/api/neurobench/compare/encoding` | Compare encoding strategies. |
| `GET` | `/api/neurobench/regression/{benchmark_id}/trends` | Fetch trend/regression analysis for a benchmark. |

## Robustness

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurobench/faults/sweep` | Run a fault-injection robustness sweep. |
| `POST` | `/api/neurobench/perturbation/sweep` | Run an input perturbation sweep. |

## Baselines, Results, and Reports

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurobench/baselines` | List saved baseline ids. |
| `POST` | `/api/neurobench/baselines` | Save a benchmark result as a baseline. |
| `GET` | `/api/neurobench/results` | List benchmark results. |
| `GET` | `/api/neurobench/results/{result_id}` | Fetch one benchmark result. |
| `POST` | `/api/neurobench/report` | Generate a benchmark report. |

## Hardware-Specific Benchmark Routes

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurobench/pynq/run` | Start a PYNQ benchmark run. |
| `GET` | `/api/neurobench/pynq/results/{run_id}` | Fetch PYNQ benchmark result. |
| `GET` | `/api/neurobench/pynq/power_trace/{run_id}` | Fetch PYNQ power trace data. |
| `POST` | `/bench/spinnaker2/run` | Start a SpiNNaker2 benchmark run. |
| `GET` | `/bench/spinnaker2/results/{run_id}` | Fetch SpiNNaker2 benchmark result. |
| `POST` | `/bench/synsense/run` | Start a SynSense benchmark run. |
| `GET` | `/bench/synsense/results/{run_id}` | Poll SynSense benchmark job status. |
| `GET` | `/bench/synsense/results/{run_id}/data` | Fetch completed SynSense benchmark data. |

Hardware-specific benchmark routes depend on optional extras or remote hardware
services. Route presence does not mean PYNQ, SpiNNaker2, SynSense, or related
SDKs are installed on the current host.

## Related Docs

- [`../neurobench_spec.md`](../neurobench_spec.md) describes product-level endpoint intent.
- [`developer/adding_new_metric.md`](developer/adding_new_metric.md) explains adding metrics.
- [`archive/pynq_integration_plan.md`](archive/pynq_integration_plan.md) covers PYNQ benchmark strategy.
- [`archive/spinnaker2_integration_plan.md`](archive/spinnaker2_integration_plan.md) covers SpiNNaker2 benchmark strategy.
- [`archive/integration/synsense_integration_plan.md`](archive/integration/synsense_integration_plan.md) covers SynSense benchmark strategy.
