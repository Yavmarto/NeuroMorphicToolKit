# NMTK API Documentation

This page is the suite-level entrypoint for toolkit APIs. The live FastAPI
OpenAPI documents are the source of truth for exact request and response
schemas. These Markdown docs explain where each service runs, how to inspect
the live API, and which module guide contains human-oriented examples.

Do not maintain a separate generated endpoint catalog here. Use
`nmtk/neuro_toolkit/assets/modules.json` for module ids, ports, run paths, and
uvicorn targets, and use each service's `/openapi.json` for the current route
schema.

## Live API Inspection

For any running backend:

```bash
curl http://127.0.0.1:<port>/health
open http://127.0.0.1:<port>/docs
curl http://127.0.0.1:<port>/openapi.json
```

The repository helper uses the launcher manifest instead of a duplicated port
table:

```bash
python3 scripts/backend_endpoint_smoke.py list
python3 scripts/backend_endpoint_smoke.py health --module all
python3 scripts/backend_endpoint_smoke.py openapi --module neurocnl
python3 scripts/backend_endpoint_smoke.py smoke --module neurocnl --start
```

See [`docs/agents/nmtk-backend-smoke.md`](../agents/nmtk-backend-smoke.md) for
the full endpoint smoke workflow.

## Service Index

| Module id | Service | Default base URL | Live docs | Human API guide | Auth notes |
| --- | --- | --- | --- | --- | --- |
| `neurocnl` | CNL Studio | `http://127.0.0.1:8000` | `/docs`, `/openapi.json` | [`neurocnl/docs/api_reference.md`](../../neurocnl/docs/api_reference.md) | Optional `X-API-Key` when `AUTH_ENABLED=true`. |
| `Neurosim` | NeuroSim | `http://127.0.0.1:8001` | `/docs`, `/openapi.json` | [`Neurosim/docs/api_documentation.md`](../../Neurosim/docs/api_documentation.md) | No API-key gate in the current app. |
| `Neurochip` | NeuroChip | `http://127.0.0.1:8002` | `/docs`, `/openapi.json` | [`Neurochip/docs/neurochip/api_reference.md`](../../Neurochip/docs/neurochip/api_reference.md) | Optional `X-API-Key` when `NEUROCHIP_AUTH_ENABLED=true`. |
| `Neurobench` | NeuroBench | `http://127.0.0.1:8003` | `/docs`, `/openapi.json` | [`Neurobench/docs/api_reference.md`](../../Neurobench/docs/api_reference.md) | Optional `X-API-Key` when `NB_AUTH_ENABLED=true`. |
| `Neurosense` | NeuroSense | `http://127.0.0.1:8004` | `/docs`, `/openapi.json` | [`Neurosense/docs/api_documentation.md`](../../Neurosense/docs/api_documentation.md) | Optional `X-API-Key` header or `api_key` query when `NEUROSENSE_AUTH_ENABLED=true`. |
| `Neurohub` | NeuroHub | `http://127.0.0.1:8005` | `/docs`, `/openapi.json` | [`Neurohub/docs/neurohub/api_reference.md`](../../Neurohub/docs/neurohub/api_reference.md) | Optional API key or JWT when `NEUROHUB_AUTH_ENABLED=true`. |
| `neuro_dream_hand` | NDH Simulator | No HTTP service | Not applicable | [`Neuro-Dream-Hand/docs/api.md`](../../Neuro-Dream-Hand/docs/api.md) | Python package API only. |

## Common Endpoints

Every runnable HTTP module exposes:

- `GET /health` for local readiness.
- `GET /docs` for Swagger UI, unless explicitly customized.
- `GET /openapi.json` for the current OpenAPI schema.

Some services also expose operational routes:

- `neurocnl`: `GET /metrics` for Prometheus metrics.
- `Neurochip`: `/hardware/pynq/*` for board-local PYNQ runtime operations.
- `Neurobench`: `/bench/*` for selected hardware benchmark runners.

## Support-Level Rules

The docs must preserve the repo's support semantics:

- OpenAPI route presence does not mean hardware is connected or supported.
- Export endpoints can generate artifacts without proving hardware deployment.
- Optional dependencies such as MuJoCo, BrainFlow, PYNQ, Akida, Lava, and
  SpiNNaker must stay optional and may report degraded capability.
- Hardware-specific guides must say whether a flow is scaffold/export-only,
  simulator-backed, or real-board verified.

Use these references for hardware truthfulness:

- [`neurocnl/docs/support_matrix.md`](../../neurocnl/docs/support_matrix.md)
- [`docs/AKIDA_SUPPORT_SEMANTICS.md`](../AKIDA_SUPPORT_SEMANTICS.md)
- [`docs/PYNQ_SUPPORT_SEMANTICS.md`](../PYNQ_SUPPORT_SEMANTICS.md)
- [`docs/Release readiness/TEENSY_RELEASE_READINESS.md`](../Release%20readiness/TEENSY_RELEASE_READINESS.md)

## Documentation Maintenance

When adding or changing an endpoint:

1. Update the owning router and schema tests.
2. Confirm the route appears in `/openapi.json`.
3. Update the owning module's human API guide with intent, auth, example
   payloads, and hardware or optional-extra caveats.
4. Update this index only if a service, port, module id, auth mode, or guide
   location changes.
5. For cross-module or launcher-visible behavior, follow root `AGENTS.md` and
   run the required owner and integration checks.
