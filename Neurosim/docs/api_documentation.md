# NeuroSim API Documentation

This page documents the human-facing NeuroSim HTTP API. The live OpenAPI schema
at `/openapi.json` is authoritative for exact request and response models.

Default base URL: `http://127.0.0.1:8001`

Live docs:

- Swagger UI: `http://127.0.0.1:8001/docs`
- OpenAPI JSON: `http://127.0.0.1:8001/openapi.json`
- Health: `http://127.0.0.1:8001/health`

## Authentication

The current NeuroSim backend does not enforce API-key authentication. It does
apply CORS, request logging, and rate limiting.

## Operational Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Service health check. |
| `GET` | `/docs` | FastAPI Swagger UI. |
| `GET` | `/openapi.json` | Canonical generated OpenAPI schema. |
| `GET` | `/` | Frontend mount or fallback API message. |

## Projects

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurosim/projects` | Create a saved canvas project. |
| `GET` | `/api/neurosim/projects` | List project summaries. |
| `GET` | `/api/neurosim/projects/{project_id}` | Fetch one saved project including graph and CNL spec. |

Example create request:

```json
{
  "name": "My New Project",
  "description": "Example description",
  "graph": {
    "nodes": [],
    "edges": [],
    "metadata": {}
  }
}
```

## Components and Templates

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurosim/components` | List available canvas component blocks. |
| `GET` | `/api/neurosim/components/categories` | List component categories. |
| `GET` | `/api/neurosim/templates` | List starter templates. |
| `GET` | `/api/neurosim/templates/{id}` | Fetch a starter template. |

## Validation and CNL Sync

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurosim/validate` | Validate a canvas graph. |
| `POST` | `/api/neurosim/generate-cnl` | Convert a canvas graph into CNL text. |
| `POST` | `/api/neurosim/parse-cnl` | Convert CNL text into a canvas graph. |

Validation request body: `CanvasGraph`.

`generate-cnl` request body: `CanvasGraph`.

`parse-cnl` request body: `CnlRequest`.

## Simulation and Preview

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurosim/preview` | Start or run a preview simulation for a graph. |
| `GET` | `/api/neurosim/simulations/{job_id}` | Poll preview simulation status or result. |
| `POST` | `/api/neurosim/simulations/{job_id}/cancel` | Cancel a running simulation job. |
| `WS` | `/api/neurosim/ws/simulation` | WebSocket simulation stream for progressive updates. |

Example preview request:

```json
{
  "graph": {
    "nodes": [],
    "edges": [],
    "metadata": {}
  },
  "duration": 1.0,
  "dt": 0.001
}
```

## Parameter Sweeps

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurosim/sweep` | Start a parameter sweep. |
| `GET` | `/api/neurosim/sweep/{job_id}` | Poll sweep status and results. |
| `GET` | `/api/neurosim/export/sweep/{job_id}/{format}` | Export completed sweep results. |

Example sweep request:

```json
{
  "graph": {
    "nodes": [],
    "edges": [],
    "metadata": {}
  },
  "parameter_path": "nodes.node_1.tau_rc",
  "start": 0.01,
  "end": 0.05,
  "steps": 5
}
```

## Export

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurosim/export/{format}` | Export a graph or simulation artifact. |

Supported formats are defined by the backend and should be verified through
`/openapi.json` and the export router. Common formats include CNL, Python, C,
NeuroML, and SVG depending on graph support.

## Hardware and Optional Paths

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/sim/spinnaker2/run` | Run a SpiNNaker2-oriented simulation path. |
| `GET` | `/api/sim/spinnaker2/results/{run_id}` | Fetch SpiNNaker2 simulation result payload. |

SpiNNaker2 support depends on optional runtime/toolchain availability. Route
presence does not imply physical board availability.

## Related Docs

- [`../neurosim_spec.md`](../neurosim_spec.md) describes the product-level API intent.
- [`neurocnl_runtime_alignment.md`](neurocnl_runtime_alignment.md) explains NeuroCNL alignment.
- [`developer-guide/adding_new_component.md`](developer-guide/adding_new_component.md) covers component extension.
