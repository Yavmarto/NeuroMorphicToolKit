# NeuroChip API Reference

This page documents the human-facing NeuroChip HTTP API. The live OpenAPI
schema at `/openapi.json` is authoritative for exact request and response
models.

Default base URL: `http://127.0.0.1:8002`

Live docs:

- Swagger UI: `http://127.0.0.1:8002/docs`
- OpenAPI JSON: `http://127.0.0.1:8002/openapi.json`
- Health: `http://127.0.0.1:8002/health`

## Authentication

API-key authentication is optional. When `NEUROCHIP_AUTH_ENABLED=true`, all
registered router endpoints require:

```http
X-API-Key: <NEUROCHIP_API_KEY>
```

`/health`, `/docs`, and `/openapi.json` remain public.

## Operational Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Service health check. |
| `GET` | `/docs` | FastAPI Swagger UI. |
| `GET` | `/openapi.json` | Canonical generated OpenAPI schema. |

## Target Discovery and Analysis

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurochip/targets` | List hardware target profiles. |
| `GET` | `/api/neurochip/targets/{id}` | Fetch one hardware target profile. |
| `POST` | `/api/neurochip/analyze` | Run hardware-constraint analysis for a network and target. |
| `POST` | `/api/neurochip/partition` | Suggest partitioning for a target. |
| `POST` | `/api/neurochip/compare` | Compare multiple target profiles for a network. |

Target metadata comes from `neurochip/targets/*.json`. Do not treat a target
profile as proof that a physical device is connected.

## Quantization, Faults, and Estimates

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurochip/quantize` | Run one quantization analysis. |
| `POST` | `/api/neurochip/quantize/batch` | Run multiple quantization levels. |
| `POST` | `/api/neurochip/quantize/configure` | Return or validate quantization configuration. |
| `POST` | `/api/neurochip/faults` | Run a fault injection sweep. |
| `POST` | `/api/neurochip/estimate/power` | Estimate power for a network and target. |
| `POST` | `/api/neurochip/estimate/latency` | Estimate latency for a network and target. |

## Artifact Export

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurochip/export/akida` | Generate an Akida-oriented export artifact. |
| `POST` | `/api/neurochip/export/brainscales` | Generate a BrainScaleS-oriented artifact. |
| `POST` | `/api/neurochip/export/spinnaker` | Generate a SpiNNaker-oriented artifact. |
| `POST` | `/api/neurochip/export/teensy` | Generate a Teensy firmware project/archive. |
| `POST` | `/api/neurochip/export/loihi` | Generate a Loihi-oriented deployment package. |
| `POST` | `/api/neurochip/export/lava` | Generate a Lava deployment script/package. |
| `POST` | `/api/neurochip/export/pynq` | Generate a PYNQ runtime/export package. |
| `POST` | `/api/neurochip/export/neuroml` | Export to NeuroML format. |
| `WS` | `/api/neurochip/export/ws/compile` | WebSocket compile/progress channel. |

Export route success means artifact generation succeeded. It does not prove
hardware compilation, flashing, mapping, or inference.

## Serial and Teensy Flashing

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurochip/serial/ports` | List available serial ports. |
| `POST` | `/api/neurochip/serial/flash` | Start a firmware compile/flash job. |
| `GET` | `/api/neurochip/serial/flash/{job_id}` | Poll flash job status. |
| `POST` | `/api/neurochip/serial/flash/{job_id}/verify` | Trigger post-flash verification. |

Do not hardcode serial ports. Hardware may be absent in CI and local development.

## Deployment Records

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/neurochip/deployments` | List deployment records. |
| `POST` | `/api/neurochip/deployments` | Record a deployment event. |
| `POST` | `/api/neurochip/deployments/validate` | Validate a deployment manifest. |

## Akida Runtime

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurochip/akida/deploy` | Build or deploy an Akida model from a network payload. |
| `POST` | `/api/neurochip/akida/deploy/mapped` | Deploy a mapped payload from the NeuroCNL Akida handoff. |
| `POST` | `/api/neurochip/akida/map` | Canonical runtime mapping action for a mapped Akida payload. |
| `POST` | `/api/neurochip/akida/inference` | Run inference against an Akida runtime target when available. |
| `GET` | `/api/neurochip/akida/status` | Report Akida SDK/device availability. |
| `POST` | `/api/neurochip/akida/verify` | Deprecated compatibility route; use `/map` for mapping and `/status` for status checks. |

Akida support is optional and environment-dependent. Missing BrainChip SDK or
device access must be reported as runtime capability state, not as base server
startup failure. The `status` and `verify` payloads now include
`environment_checks` describing host OS support, Python-range compatibility,
MetaTF package availability (`tensorflow`, `cnn2snn`, `akida-models`), and the
recommended local runtime mode.

## PYNQ Runtime

These routes are intentionally not under `/api/neurochip`; they are used by the
board-local PYNQ runtime flow.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/hardware/pynq/deploy` | Deploy a PYNQ runtime package. |
| `POST` | `/hardware/pynq/run` | Run a PYNQ inference/execution request. |
| `GET` | `/hardware/pynq/status` | Report board/runtime status. |
| `GET` | `/hardware/pynq/preflight` | Report preflight readiness for PYNQ runtime work. |
| `POST` | `/hardware/pynq/verify` | Run verification checks after deployment. |

Use [`pynq_z2_deployment_guide.md`](pynq_z2_deployment_guide.md) for board
setup and real-board caveats.

## Lava and SpiNNaker2 Runtime Routes

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/neurochip/hardware/lava/compile` | Compile/prep a Lava runtime payload. |
| `POST` | `/api/neurochip/hardware/lava/run` | Run a Lava runtime payload. |
| `POST` | `/api/neurochip/hardware/lava/stop` | Stop a Lava runtime session. |
| `POST` | `/api/neurochip/hardware/spinnaker2/compile` | Compile/prep a SpiNNaker2 runtime payload. |
| `POST` | `/api/neurochip/hardware/spinnaker2/run` | Run a SpiNNaker2 payload. |
| `POST` | `/api/neurochip/hardware/spinnaker2/stream` | Start or manage SpiNNaker2 streaming. |

Lava and SpiNNaker2 dependencies are optional extras. Route availability does not
guarantee the vendor SDK or board is installed.

## Related Docs

- [`../../neurochip_spec.md`](../../neurochip_spec.md) describes product-level API intent.
- [`user_guide.md`](user_guide.md) covers the UI deployment workflow.
- [`developer_guide.md`](developer_guide.md) covers adding target profiles.
- [`pynq_z2_deployment_guide.md`](pynq_z2_deployment_guide.md) covers board-local PYNQ runtime setup.
- [`../ADR-claude/0003-optional-api-key-authentication.md`](../ADR-claude/0003-optional-api-key-authentication.md) explains optional auth.
