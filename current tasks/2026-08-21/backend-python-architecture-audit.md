# Python Audit Report — NMTK Backend

**Date:** 2026-08-21  
**Scope:** `suite_api/`, `workers/`, `nmtk/launcher_control/`, root Compose wiring, persistence boundaries, and cross-module backend tests  
**Method:** Read-only static architecture review plus Ruff, mypy, pytest, and launcher-doctor verification  

## Audit Health Score: 10/32 — Poor

The backend should not be approved for untrusted or multi-user production use with the blocking issues below unresolved. The core modular-monolith design is sensible, but its security boundary, persistence ownership, diagnostic behavior, and verification pipeline are not yet strong enough.

| Dimension | Score | Notes |
|---|---:|---|
| Type Safety | 1 | Suite API mypy reported 16 errors; workers and launcher reported 315, including unsafe `None` access and undeclared mixin state |
| Architecture | 1 | Good modular-monolith idea, but broken storage ownership, disabled NeuroHub wiring, raw SQLite services, and an oversized launcher server |
| Error Handling | 2 | Worker failures usually become 503 responses, but broad catches, swallowed exceptions, and inconsistent error envelopes remain |
| Testing | 1 | Suite tests cannot collect in the available environment; cross-module tests use retired service addresses and are not currently dependable gates |
| Performance | 1 | One API process, synchronous SQLite access, process-local jobs, and blocking subprocess calls inside asynchronous endpoints |
| Security | 1 | Launcher-control is publicly bound, unauthenticated, mutation-capable, and returns wildcard CORS headers |
| Module Boundaries | 2 | Strong Pydantic and hardware contracts exist, but manifests, health checks, persistence, tests, and documentation have drifted |
| Documentation | 1 | Monitoring and module documentation contradict current Compose and Suite API behavior |

## Architecture Summary

NMTK uses a modular monolith for ordinary backend work. The Flutter application calls one FastAPI Suite API on port 9000, which mounts NeuroStudio, NeuroSim, NeuroChip, NeuroBench, NeuroSense, and Jupyter control routes in one process.

Hardware access and unusually heavy dependencies are isolated in workers:

- NeuroChip hardware and native runtime access on port 8002
- NeuroBench execution on port 8003
- NeuroSense hardware access on port 8004
- MuJoCo physics on port 8006
- SNN-MLIR compilation on port 8007
- JupyterLab on port 8008
- Lava runtime on port 8012

Launcher-control is a separate control plane, internally on port 8091 and normally published on port 8090. It manages readiness, settings, workspace navigation state, deployment targets, Akida hosts, PYNQ boards, and provisioning operations.

This separation is directionally correct: lightweight product behavior stays simple and in-process, while proprietary, hardware-specific, or heavyweight runtimes cannot prevent the base service from starting. The tradeoff is that Suite API becomes a shared failure domain and all persistence, security, middleware, and startup behavior must be correct centrally.

## Blocking Issues — P0

### 1. Launcher-control has no adequate remote security boundary

Launcher-control binds to all interfaces and exposes settings, workspace, deployment, hardware discovery, Akida, PYNQ, and provisioning mutations without a common authentication or authorization layer. Its HTTP transport returns `Access-Control-Allow-Origin: *`, so it should be treated as trusted-network-only until authentication, authorization, TLS, and tighter origin controls are enforced.

Relevant files:

- `nmtk/launcher_control/http_server.py`
- `nmtk/launcher_control/http_transport.py`
- `nmtk/launcher_control/server.py`
- `docker-compose.yml`

### 2. Production persistence ownership is inconsistent

Several stateful features do not reliably write to the named volume intended to preserve their data:

- NeuroSim projects default to `projects.db` in the current working directory, which is `/repo` in the read-only production Suite API container
- NeuroChip deployment history defaults beneath the installed source tree, also read-only in production
- NeuroSense recording routes run in Suite API, while the persistent recordings volume is mounted on the hardware worker
- Some benchmark worker state defaults to `/tmp`, despite a named `/app/data` volume
- Akida model state defaults to temporary storage unless explicitly redirected
- Benchmark execution and result-reading can use different databases in different containers

These mismatches can cause failed writes, missing results, or data disappearing after a container restart.

Relevant files:

- `docker-compose.yml`
- `docker-compose.prod.yml`
- `neurocnl/neurosim/app/services/project_store.py`
- `Neurochip/neurochip/app/services/deployment_store.py`
- `Neurosense/neurosense/app/services/recording_service.py`
- `Neurobench/neurobench/app/services/result_store.py`
- `Neurochip/neurochip/app/services/akida_model_jobs.py`

### 3. Launcher doctor is not genuinely non-mutating

Running the documented doctor command started a local Akida runtime process before producing its report. The process had terminated when checked after the command, but a diagnostic advertised as non-mutating must not start runtime services at all.

The doctor result also reported:

- `fatalCount: 2`
- `degradedCount: 1`
- Flutter SDK cache not writable: preflight failed
- Suite API not reachable from launcher control: preflight failed
- Missing optional Studio SDKs and Lava worker: degraded optional capability

### 4. The required verification gates are not currently reliable

Suite API tests could not collect in the available environment because `aiosqlite` and `watchdog` were missing. The root integration tests also lacked async pytest support in the available environment, and their source still defaults to retired per-module service addresses rather than the consolidated Suite API on port 9000.

## Major Issues — P1

### NeuroHub is present but disabled

NeuroHub is installed into the Suite API image and still appears in module health expectations, but its router and lifespan calls are commented out in `suite_api/main.py`. This creates a false architectural claim: the code exists, yet its routes and database migrations are not active.

The project should either enable NeuroHub completely with migrations and tests or remove its active manifest and health claims until it is ready.

### Type checking does not model the real architecture

Suite API mypy analysis reported 16 errors, many caused by missing package configuration and untyped imported modules. Worker and launcher analysis reported 315 errors, including genuine unsafe access in runtime-contract parsing and widespread mixin attributes that are only supplied dynamically by the final combined state class.

The launcher mixins need typed protocols or explicit base-state interfaces so mypy can verify their assumptions. Workers also need proper package boundaries and their own mypy configuration so multiple files named `main.py` are not interpreted as duplicate modules.

### Linting is not green

Ruff reported 136 findings across Suite API, workers, and launcher-control. Many are mechanical, but the important findings include swallowed exceptions, unlogged `except: pass` paths, broad exception handling, blocking subprocess execution inside async handlers, and stale suppressions.

### Async endpoints perform blocking work

The SNN-MLIR compile endpoint calls `subprocess.run` directly inside an asynchronous route. Synchronous SQLite access and CPU-heavy work in other routes can similarly block the single Suite API event loop.

Blocking operations should move to worker threads, process pools, or background workers with explicit timeouts and cancellation.

### Job ownership is fragmented

NeuroCNL jobs are durable in SQLite, NeuroSim jobs are process-local, benchmark jobs can live in a worker-specific database, Jupyter has a separate registry, and hardware runtimes use their own state. This makes cancellation, crash recovery, result lookup, and multi-instance deployment inconsistent.

### Observability documentation is stale

Prometheus, Loki, Grafana, Promtail, and Alertmanager configuration remains in `monitoring/`, and ADRs describe a monitoring Compose profile. The current root Compose files do not launch that stack, and Alertmanager notification delivery was never configured beyond a null receiver.

### Error contracts are inconsistent

Suite API has a generic JSON 500 handler and the worker proxy maps connection failures to 503, which are useful foundations. However, launcher-control exposes raw exception strings, the proxy response includes internal worker URLs, and individual domains retain different error shapes and logging behavior.

## Suggestions — P2

- Put ports 9000 and 8090 behind an authenticated TLS boundary
- Require authorization for launcher mutations and hardware provisioning
- Move every durable path beneath an explicitly owned persistent volume
- Establish one authoritative benchmark job-and-result store
- Enable NeuroHub fully or remove false active-service claims
- Rewrite cross-module tests around one `SUITE_API_URL`
- Make required unavailable routes fail rather than skip
- Add Suite API and Compose integration checks as first-class CI jobs
- Use PostgreSQL before horizontal scaling or multi-user deployment
- Store large artifacts in object storage rather than container-local files
- Use a durable task queue for long-running and recoverable work
- Add restart-persistence tests for every database, recording, notebook, model, and deployment record
- Add contract tests proving real hardware, simulator, and estimated results cannot be confused
- Restore the monitoring stack or archive its stale operational claims
- Add distributed tracing after authentication and request correlation are stable

## Positive Findings

- Consolidating ordinary routes into Suite API removes unnecessary internal HTTP calls
- Heavy and hardware-specific runtimes are isolated from the core authoring workflow
- Missing optional runtimes generally degrade capability instead of crashing the base service
- Production containers use non-root users, read-only filesystems, dropped capabilities, and `no-new-privileges`
- Important hardware handoffs use typed Pydantic contracts and versioned artifacts
- Worker connection failures normally become HTTP 503 rather than misleading internal errors
- NeuroCNL persists job progress events and attempts crash recovery
- The deployment update path preserves named volumes unless an explicit clean install is requested

## Verification Commands Run

### Ruff

```bash
Neurochip/.venv/bin/ruff check suite_api workers nmtk/launcher_control
```

Result: failed with 136 findings, 84 reported as automatically fixable.

### Suite API mypy

```bash
Neurochip/.venv/bin/mypy suite_api
```

Result: failed with 16 errors in 9 files, including missing module configuration and an unproven `neurocnl.__version__` attribute.

### Worker and launcher mypy

```bash
Neurochip/.venv/bin/mypy --explicit-package-bases workers nmtk/launcher_control
```

Result: failed with 315 errors in 23 files, combining environment/import issues with genuine launcher mixin and runtime-contract typing defects.

### Suite API tests

```bash
env -u PYTEST_ADDOPTS PYTHONPATH=.:neurocnl:Neurochip:Neurobench/neurobench:Neurosense:Neurohub Neurochip/.venv/bin/pytest -q suite_api/tests
```

Result: collection stopped with 2 import errors because the available environment lacks `aiosqlite` and `watchdog`; no test result was treated as passing.

### Cross-module tests

```bash
env -u PYTEST_ADDOPTS Neurochip/.venv/bin/pytest -q tests/integration/test_cross_module.py
```

Result: 8 harness failures because the available environment lacks async pytest support; these were not application assertion failures.

### Teensy end-to-end tests

```bash
env -u PYTEST_ADDOPTS Neurochip/.venv/bin/pytest -q tests/integration/test_teensy_e2e.py
```

Result: 11 harness failures for the same missing async pytest support; these were not application assertion failures.

### Launcher doctor

```bash
Neurochip/.venv/bin/python scripts/launcher_control_service.py --doctor --json
```

Result: preflight failed with 2 fatal checks and 1 degraded optional capability; the command also unexpectedly started a local Akida runtime during the diagnostic and therefore violated its non-mutating contract.

## Recommended Remediation Order

1. Secure Suite API and launcher-control network access
2. Correct all persistent storage paths and volume ownership
3. Make launcher doctor non-mutating and clear its fatal findings
4. Enable or truthfully disable NeuroHub across all surfaces
5. Build a complete Suite API test environment and make it a CI gate
6. Rewrite integration tests for the port-9000 consolidated architecture
7. Fix job and result ownership across Suite API and workers
8. Address blocking async work and high-value Ruff and mypy findings
9. Restore or retire the monitoring stack
10. Introduce PostgreSQL, object storage, and a durable queue before scaling horizontally

## Approval Decision

**Rejected for untrusted or multi-user production deployment in its current state.** The architecture can be conditionally acceptable for development or a tightly trusted single-lab environment, provided operators understand the persistence and security limitations.
