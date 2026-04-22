# NMTK Backend Smoke-Test Agent Guide

Use this guide when an agent needs to verify backend endpoint work in the
NeuroMorphicToolKit suite. Keep endpoint discovery live: read OpenAPI and tests
instead of copying route catalogs into this file.

## Read First

Before editing or testing backend work:

- Read root `AGENTS.md`.
- Read root `CODING_STYLE_GUIDE.md`.
- Read the owning module `AGENTS.md` before editing that module.
- If a change crosses a contract boundary, read both modules' `AGENTS.md` files
  and both sides' relevant spec, ADR, or contract tests before writing.

Use `nmtk/neuro_toolkit/assets/modules.json` as the source of truth for module
ids, ports, install paths, run paths, and uvicorn targets. Do not keep a
separate static table of backend ports or endpoints.

## Helper Script

Run the root helper from the repository root:

```bash
python3 scripts/backend_endpoint_smoke.py --help
python3 scripts/backend_endpoint_smoke.py list
```

Common commands:

```bash
python3 scripts/backend_endpoint_smoke.py health --module all
python3 scripts/backend_endpoint_smoke.py health --module neurocnl
python3 scripts/backend_endpoint_smoke.py openapi --module neurocnl
python3 scripts/backend_endpoint_smoke.py call --module neurocnl --method POST --path /api/parse --json '{"spec":"The sensory neuron MUST fire"}'
python3 scripts/backend_endpoint_smoke.py smoke --module neurocnl
```

To start a single backend for a smoke run:

```bash
python3 scripts/backend_endpoint_smoke.py smoke --module neurocnl --start
```

`--start` uses the module's manifest entry: `.venv` or `venv` Python, manifest
`runPath`, manifest `uvicornTarget`, manifest port, and host `127.0.0.1`.
It does not kill an existing process on the port. If a port is already in use,
reuse the running service with `health`, `openapi`, or `call`, or stop it
explicitly yourself.

Use `--keep-running` only when the agent should leave a manually started backend
up for follow-up calls:

```bash
python3 scripts/backend_endpoint_smoke.py smoke --module neurocnl --start --keep-running
```

## Workflows

For single-module endpoint work:

1. Read the module's `AGENTS.md` and relevant tests or route files.
2. Run `python3 scripts/backend_endpoint_smoke.py list` to confirm the module id.
3. Start or reuse the backend.
4. Run `health`, then `openapi`, then targeted `call` checks for changed routes.
5. Run the owning module's test command from its own config.

For already-running services:

```bash
python3 scripts/backend_endpoint_smoke.py health --module all
python3 scripts/backend_endpoint_smoke.py openapi --module <module-id>
```

For Docker suite testing, use the root compose files and the existing root
integration tests. The helper is for lightweight endpoint probing, not full
container orchestration.

For cross-module contract work, run the root integration checks after owning
module checks:

```bash
python3 -m pytest tests/integration/test_cross_module.py
python3 -m pytest tests/integration/test_teensy_e2e.py
```

For launcher or control-plane behavior, run the canonical launcher wrapper:

```bash
bash scripts/run_launcher_guardrails.sh
```

Use `bash scripts/run_launcher_guardrails.sh --with-integration` when launcher
changes affect module contracts or suite-visible startup behavior.

## Endpoint Discovery

Prefer these sources, in order:

- `/openapi.json` from the live backend.
- The owning module's FastAPI routers and schemas.
- Existing endpoint tests in the owning module.
- Root integration tests for suite-level contracts.

If `/health` returns HTTP 503, treat it as degraded optional capability and
inspect the body. Do not collapse degraded optional capability into a generic
startup failure.
