# NMTK API Documentation

This is the suite-level entrypoint for backend docs.

The current backend model is:

- `suite_api` is the canonical FastAPI service on `http://127.0.0.1:9000`
- module domains are mounted in-process under `/api/{module}/`
- optional workers exist only for hardware, jobs, or heavy optional runtimes

## Canonical Inspection Points

For the unified backend:

```bash
curl http://127.0.0.1:9000/api/suite/health
open http://127.0.0.1:9000/docs
curl http://127.0.0.1:9000/openapi.json
```

For repo-aware smoke testing:

```bash
python3 scripts/backend_endpoint_smoke.py list
python3 scripts/backend_endpoint_smoke.py health --module all
python3 scripts/backend_endpoint_smoke.py openapi --module neurocnl
python3 scripts/backend_endpoint_smoke.py smoke --module neurocnl --start
```

See [`../agents/nmtk-backend-smoke.md`](../agents/nmtk-backend-smoke.md) for the full workflow.

## Domain Index

All standard module APIs are served by `suite_api` on port `9000`:

| Domain | Base path | Notes | Human guide |
| --- | --- | --- | --- |
| `neurocnl` | `/api/neurocnl` | canonical CNL parse, validate, generate, simulate, export, deploy, templates, Studio handoff | [`../../neurocnl/docs/api_reference.md`](../../neurocnl/docs/api_reference.md) |
| `neurosim` | `/api/neurosim` | canvas, project, preview, sweep, export flows | module-local docs and contracts |
| `neurochip` | `/api/neurochip` | target, deployment, hardware, analysis, and execution flows | [`../../Neurochip/docs/neurochip/api_reference.md`](../../Neurochip/docs/neurochip/api_reference.md) |
| `neurobench` | `/api/neurobench` | benchmarks, comparisons, baselines, results, regression, reports | [`../../Neurobench/docs/api_reference.md`](../../Neurobench/docs/api_reference.md) |
| `neurosense` | `/api/neurosense` | presets, encoding, recording, sessions, export, quality | [`../../Neurosense/docs/api_documentation.md`](../../Neurosense/docs/api_documentation.md) |
| `neurohub` | `/api/neurohub` | registry, project metadata, workflow metadata, assets, notes, members | [`../../Neurohub/docs/neurohub/api_reference.md`](../../Neurohub/docs/neurohub/api_reference.md) |

## Optional Workers

These are not the default API entrypoint. They exist to isolate hardware or heavy runtimes:

| Worker | Port | Used for |
| --- | --- | --- |
| `neurochip-hw-worker` | `8002` | PYNQ, Akida, Lava, serial-flash, board-specific runtime paths |
| `neurobench-runner-worker` | `8003` | long-running benchmark jobs |
| `neurosense-hw-worker` | `8004` | BrainFlow, device IO, live streams, Prophesee, hardware-facing routes |
| `neurocnl-physics-worker` | `8006` | MuJoCo-backed prosthetic simulation |

Canonical clients should call `suite_api`; worker-backed routes are proxied or explicitly delegated from there.

## Support Rules

- OpenAPI presence does not imply physical hardware is connected.
- Export or deploy route presence does not automatically mean real-board validation exists.
- Optional dependencies must degrade capability rather than crash the base service.
- For launcher-visible metadata, ports, and run targets, use [`../../nmtk/neuro_toolkit/assets/modules.json`](../../nmtk/neuro_toolkit/assets/modules.json) as the source of truth.

## Maintenance

When backend behavior changes:

1. Update the owning router, service, and tests.
2. Confirm the change appears in `suite_api`'s `/openapi.json`.
3. Update the owning human API guide if examples, auth notes, or semantics changed.
4. Update this README only when the suite-level topology, domain path, guide location, or worker model changed.
