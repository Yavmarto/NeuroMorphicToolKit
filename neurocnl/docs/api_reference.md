# NeuroCNL API Reference

This page documents the human-facing NeuroCNL HTTP API. The live OpenAPI schema
at `/openapi.json` is authoritative for exact request and response models.

Default base URL: `http://127.0.0.1:8000`

Live docs:

- Swagger UI: `http://127.0.0.1:8000/docs`
- OpenAPI JSON: `http://127.0.0.1:8000/openapi.json`
- Health: `http://127.0.0.1:8000/health`

## Authentication

API-key authentication is optional. When `AUTH_ENABLED=true`, all `/api/*`
routes require:

```http
X-API-Key: <API_KEY>
```

`/health`, `/docs`, `/openapi.json`, and `/metrics` are outside the `/api`
middleware gate.

## Operational Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Reports service readiness, optional module availability, NeuroCNL version, and disk status. |
| `GET` | `/docs` | Custom Swagger UI for the live API. |
| `GET` | `/openapi.json` | Canonical OpenAPI schema generated from FastAPI routes. |
| `GET` | `/metrics` | Prometheus metrics endpoint. |

## Core CNL Pipeline

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/parse` | Parse controlled-natural-language text into structured sentence results. |
| `POST` | `/api/validate` | Validate a CNL spec against invariants and backend support constraints. |
| `POST` | `/api/generate` | Generate a network representation and generated code from a valid spec. |
| `POST` | `/api/simulate` | Deprecated compatibility route. Returns `410` on the supported NIR-only surface. |
| `GET` | `/api/jobs` | List simulation or pipeline jobs. |
| `GET` | `/api/jobs/{job_id}` | Poll one job and retrieve its status/result payload. |
| `GET` | `/api/templates` | List built-in CNL templates. |
| `POST` | `/api/export` | Export the spec or generated artifact in the requested format. |

Minimal parse call:

```bash
curl -s -X POST http://127.0.0.1:8000/api/parse \
  -H "Content-Type: application/json" \
  -d '{"spec":"The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"}'
```

Studio preview is now driven by `POST /api/generate` plus optional
`POST /api/export` with `format="nir"`. The `/api/simulate` route remains
only as a deprecated compatibility endpoint and returns a structured `410`
error on the supported NIR-only surface.

## Toolkit Handoff and Deployment Gates

These endpoints prepare target-specific handoff payloads for downstream modules.
They do not by themselves prove real hardware execution.

| Method | Path | Target owner | Purpose |
| --- | --- | --- | --- |
| `POST` | `/api/deploy/teensy/network` | Neurochip | Validate the supported Teensy subset and produce a payload for Neurochip firmware generation. |
| `POST` | `/api/deploy/pynq/network` | Neurochip | Validate/export the PYNQ runtime package shape for Neurochip or board-side tooling. |
| `POST` | `/api/deploy/akida/network` | Neurochip | Validate/map the Akida subset and produce scaffold or mapped payload data for Neurochip verification. |
| `POST` | `/api/neurosim/handoff` | Neurosim | Create a canonical NeuroSim import contract from a CNL spec. |

Support caveats:

- Akida support is approximate and SDK-backed deployability must be verified by
  Neurochip in a supported runtime environment.
- PYNQ support distinguishes exportability from deployability; overlay and
  board readiness must be verified separately.
- Teensy support is intentionally narrow and must pass the toolkit deploy gate
  before firmware generation.

See [`support_matrix.md`](support_matrix.md) for current backend support terms.

## Prosthetic and Dream-Hand Routes

The `/api/prosthetic/*` routes support the prosthetic-control workflow and
integration with Neuro-Dream-Hand and Neurosense. Hardware dependencies remain
optional and must degrade capability rather than break base startup.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/prosthetic/simulate` | Run prosthetic simulation workflow. |
| `POST` | `/api/prosthetic/sleep` | Run sleep/consolidation workflow. |
| `POST` | `/api/prosthetic/export/crossbar` | Export a crossbar-oriented artifact. |
| `POST` | `/api/prosthetic/energy` | Estimate or report energy metrics for the prosthetic workflow. |
| `POST` | `/api/prosthetic/quantize` | Run quantization analysis for prosthetic models. |
| `POST` | `/api/prosthetic/fault-injection` | Run fault-injection analysis. |
| `POST` | `/api/prosthetic/neurosense/replay` | Replay a Neurosense artifact into the prosthetic flow. |
| `GET` | `/api/prosthetic/hardware/serial` | List serial hardware candidates. |
| `POST` | `/api/prosthetic/hardware/connect` | Connect to a hardware interface. |
| `POST` | `/api/prosthetic/hardware/disconnect` | Disconnect a hardware interface. |
| `GET` | `/api/prosthetic/hardware/stream` | Poll or stream hardware-facing telemetry. |

## Related Docs

- [`USER_TEST_GUIDE.md`](USER_TEST_GUIDE.md) has curl-based smoke examples.
- [`UI_SPEC.md`](UI_SPEC.md) contains older UI-oriented API examples.
- [`docs/api/pipeline.md`](api/pipeline.md) explains the Python pipeline API.
- [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md) covers deployment-oriented setup.

## Training Endpoints

The `/api/training/*` routes support the generic training workflow.
These routes are adapter-agnostic — any registered training adapter
can be targeted via `backend_name`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/training/capabilities` | List all registered training adapters with availability status. |
| `POST` | `/api/training/run` | Submit a training job for a specific backend. Returns 202 with a job ID. |
| `GET` | `/api/training/jobs/{job_id}` | Poll a training job and retrieve its status/result. |

### GET /api/training/capabilities

Returns all registered training adapters with their availability:

```bash
curl -s http://127.0.0.1:8000/api/training/capabilities
```

Response:

```json
{
  "capabilities": [
    {
      "backend_name": "sleep_pes",
      "supported_training_modes": ["offline_sleep"],
      "default_training_mode": "offline_sleep",
      "output_format": "weights",
      "available": false,
      "unavailable_reason": "neurodreamhand package is not installed"
    },
    {
      "backend_name": "snntorch",
      "supported_training_modes": ["surrogate"],
      "default_training_mode": "surrogate",
      "output_format": "weights",
      "available": false,
      "unavailable_reason": "torch is not installed. Install the training extras to enable snnTorch training."
    }
  ]
}
```

When `available` is `false`, the `unavailable_reason` field provides a
human-readable explanation. Attempting to run an unavailable backend via
`POST /api/training/run` returns HTTP 422 with structured detail
(`error: "training_request_invalid"` plus normalized `items`).

### POST /api/training/run

Submit a training job:

```bash
curl -s -X POST http://127.0.0.1:8000/api/training/run.json 2>/dev/null || curl -s -X POST http://127.0.0.1:8000/api/training/run  -H "Content-Type: application/json"  -d '{"backend_name":"sleep_pes","training_mode":"offline_sleep","payload":{"n_epochs":5}}'
```

snnTorch example:

```bash
curl -s -X POST http://127.0.0.1:8000/api/training/run \
  -H "Content-Type: application/json" \
  -d '{"backend_name":"snntorch","training_mode":"surrogate","payload":{"spec":"The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0","dataset":"n-mnist","n_epochs":3}}'
```

Request body:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `backend_name` | string | yes | Registered adapter name (from capabilities). |
| `training_mode` | string | no | Mode to use; defaults to adapter's default. |
| `payload` | object | no | Adapter-specific parameters (e.g., `n_epochs`, `spec`). |

Response: HTTP 202 with `{"job_id": "...", "status": "queued"}`.

For library callers, NeuroCNL also now exposes a thin `fit(...)` helper:

```python
from neurocnl import fit

result = fit(
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
    backend="snntorch",
    dataset="n-mnist",
    payload={"n_epochs": 3},
)
```

### GET /api/training/jobs/{job_id}

Poll the training job. Same contract as `GET /api/jobs/{job_id}`.
Returns 404 when the job does not exist.
