# Architecture & Module Contracts Deep-Dive — 2026-06-11

## Scope

Read-only analysis of NMTK's control plane, unified backend (`suite_api`),
launcher manifest, shared Dart contracts, and cross-module handoff contract.
Result: 7 concrete drift findings and an ordered implementation plan across
4 waves. The user picked "all of the above, ordered" for follow-up execution.

## Current architecture (consolidated)

| Layer | Component | Notes |
|---|---|---|
| Control plane | `nmtk/neuro_toolkit` (Flutter launcher) | `Module.fromJson` reads `nmtk/neuro_toolkit/assets/modules.json`; Provider + GoRouter (ADR 0002/0003/0004/0005) |
| Shared Dart contracts | `nmtk_module_contracts/lib/src/{api_base_url,api_exception,error_display,studio_neurochip_handoff_contract}.dart` | Resolves base URL from `SUITE_API_URL` / `API_BASE_URL`; encodes ADR 0021 handoff |
| Unified backend | `suite_api/main.py` (FastAPI on **9000**) | Mounts 8 domain routers in-process; mounts each module's static `build/web` at `/{module_id}`; Neurosim shares `neurocnl/frontend/build/web` |
| Domain routers | `suite_api/domains/{neurocnl,neurosim,neurochip,neurobench,neurosense,neurohub,jupyter}/*` | `lifespan.py` rehydrates per-domain startup (structlog, rate limiter, job store, Alembic) |
| Optional workers | `workers/{lava_backend,jupyter_server,neurobench_runner,neurochip_hw,neurocnl_physics,neurosense_hw}/` | Started only with Docker profiles (`hardware`, `jobs`, `physics`); proxied via `proxy_to_worker` → 503 when unreachable |
| Frontend hosting | `/{module_id}` StaticFiles mount in `suite_api/main.py:83-97` | `neurosim` and `neurocnl` share the same `neurocnl/frontend/build/web` |
| Health aggregation | `suite_api/routers/health.py` | Probes its own subroutes via `http://localhost:9000/api/<m>/health` (in-process) |
| ADRs | `docs/ADR-claude/0001..0025` | 0018 supersedes 0009/0014 (unified backend); 0021 codifies Studio→Neurochip handoff; 0023 makes `nmtk` the sole control plane |
| Launcher integration | `scripts/launcher_control_service.py`, `scripts/run_launcher_guardrails.sh`, `scripts/backend_endpoint_smoke.py` | `modules.json` is the single source of truth |
| Tests | `tests/integration/test_{phase*,golden_path*,cross_module,teensy_e2e}.py` | `test_cross_module.py` still references the old per-module ports (8000–8005) — see Drift #2 |

## Module contracts (what `modules.json` says)

`modules.json` declares 7 entries; `Module.fromJson` mirrors the full shape:

- **Identity:** `id`, `name`, `description`, `icon`, `version`, `required`
- **Install:** `installPath`, `sourcePath`, `runPath`, `installStrategy`, `installExtras`, `requiredImports`, `optionalImports`, `localDeps`
- **Runtime:** `startStrategy`, `uvicornTarget`, `port` (always `9000` in current manifest — see Drift #1)
- **UI:** `hasFrontend`, `frontendStatus`, `showInLauncherNav`, `jupyterKernel.displayName`
- **Deployment:** `supportedModes`, `healthPath`, `requiredPorts`, `requiredEnvironment`, `secretFields`, `defaultContainerImage`, `chartTemplateId`, `startupTimeoutSeconds`, `readinessTimeoutSeconds`
- **Module-specific:** `Neurochip` adds `optionalImports`, `akidaRuntime`, `launcherRuntime.pynq`, `launcherRuntime.akida`

## Cross-module contracts (shared types, not just HTTP)

| Contract | Producer | Consumer | Source of truth |
|---|---|---|---|
| Studio→Neurochip handoff | `neurocnl` (Studio) | `Neurochip` | `nmtk_module_contracts/lib/src/studio_neurochip_handoff_contract.dart` + ADR 0021 |
| API base URL | env (or default) | All Flutter module frontends | `nmtk_module_contracts/lib/src/api_base_url.dart` (`SUITE_API_URL` > `API_BASE_URL` > web-relative > android 10.0.2.2 > localhost) |
| Error envelope | suite_api | Flutter clients | `nmtk_module_contracts/lib/src/api_exception.dart` + `error_display.dart` |
| Proxied worker surface | Docker worker | suite_api | `suite_api/proxy.py` + `docker-compose.yml` worker profiles |
| Module metadata | `modules.json` | launcher + guardrails + smoke | single source |

## Drift findings

### Drift #1 — `modules.json` says `port: 9000` for every module
- All 5 core modules declare `port: 9000`, but the unified backend is on 9000. The field has become meaningless for in-process routes.
- `suite_api/health.py:21-26` reflects the new model (probes `localhost:9000/api/<m>/health`).
- `suite_api/config.py:16-21` still exposes per-module URL settings (`neurocnl_url=http://localhost:8000`, etc.) and `scripts/backend_endpoint_smoke.py:71-78` (`ModuleSpec.runnable`) treats `port` + `start_strategy=uvicorn` as the runnable surface, which **every** manifest entry fails.
- **Risk:** `backend_endpoint_smoke.py` cannot exercise the consolidated backend. Dart consumers likely still pass legacy per-module ports in `NmtkApiBaseUrl.resolve`.
- **Fix:** Treat manifest `port` as the deployment-mode port; add derived `effectiveBasePath` (`/api/<id>`). Update `backend_endpoint_smoke.py` to probe `/api/suite/health/modules`. Integration test: `manifest.port == settings.suite_api_port` for `startStrategy == "none"`.

### Drift #2 — `tests/integration/test_cross_module.py` still uses the pre-consolidation port map
- Lines 11-16 default to `http://<module>:8000`; line 12 says `NEUROSIM_URL=http://neurocnl:8000`.
- ADR 0018 explicitly supersedes the per-port world; this file is the only one still in it. No env override feeds it.
- **Risk:** Silently skips via `_request_or_skip` on the consolidated stack. Dead code that looks alive.
- **Fix:** Rewrite to read a single `SUITE_API_URL` (default `http://localhost:9000`); assert `/api/<m>/<route>` shapes. The `test_phase1_suite_api.py` likely already does this — confirm and either update or delete.

### Drift #3 — Mixed opinions on "Neurosim" as a separate backend
- `suite_api/main.py:85` mounts the same `neurocnl/frontend/build/web` for `neurosim` and `neurocnl` (correct).
- `suite_api/domains/neurosim/router.py` exists separately; canvas has its own route group.
- `modules.json` does **not** list `neurosim` (embedded launcher surface per README footnote).
- **Risk:** Future engineers could add `neurosim` to the manifest and accidentally re-fork it.
- **Fix:** Add a one-line comment to `modules.json` or a sibling `assets/neurosim.json` explaining that Neurosim is a route group, not a manifest entry.

### Drift #4 — Hardcoded `8002` in `Neurochip` proxy fallback path
- `docker-compose.yml:140-143` overrides `NEUROCHIP_HW_WORKER_URL=http://neurochip-hw-worker:8002` for `launcher-control`; comment also mentions `${NEUROCHIP_PORT:-18002}:8002` (host port) — two different ports on the same variable name.
- The `launcher-control` container uses `extra_hosts: host.docker.internal:host-gateway` and the *internal* URL. If anyone follows the comment and switches to `host.docker.internal:8002`, probes will fail.
- **Risk:** Confusingly documented. Code is correct; comment misleads.
- **Fix:** Tighten the comment; rename to `NEUROCHIP_HW_WORKER_DOCKER_URL` vs public `NEUROCHIP_PORT` host mapping.

### Drift #5 — `suite_api/config.py` is a holdover from the pre-consolidation layout
- `neurocnl_url`, `neurosim_url`, `neurochip_url`, `neurobench_url`, `neurosense_url`, `neurohub_url` defaults all point to `http://localhost:8000..8005`.
- After ADR 0018, these are no longer used for in-process routes. The proxy file still uses the *worker* settings (`*_hw_worker_url`, `*_runner_url`, `*_physics_worker_url`, `jupyter_worker_url`).
- **Risk:** Dead config — anyone importing `settings.neurocnl_url` will silently target a non-existent service.
- **Fix:** Confirm no live readers via grep; then remove. Add a comment pointing to ADR 0018.

### Drift #6 — `composeProfile` declared in Dart but never in JSON
- `DeploymentCapability.composeProfile` is parsed (`module.dart:282,323`) but no manifest entry sets it. Docker workers are not profile-gated in `docker-compose.yml` — they always start.
- **Risk:** Quiet divergence. If a future manifest sets `composeProfile: "hardware"`, no code will gate on it.
- **Fix:** Either delete `composeProfile` from `DeploymentCapability` and the Dart parsing, or wire it into the launcher-control compose invocation. Update ADR 0001.

### Drift #7 — ADR 0001 is missing
- `nmtk/AGENTS.md` says to read `0001-module-manifest-system.md`, but the file is absent.
- **Risk:** Lost institutional knowledge about why the manifest exists.
- **Fix:** Either restore 0001 or update `nmtk/AGENTS.md` to drop the reference.

## Things that look right

- `StudioNeurochipHandoffContract` and ADR 0021 are in lockstep; the `fromStudioTargetId` / `fromNeurochipTargetId` / `resolve` precedence matches the ADR's "target_id is the stronger contract key" rule.
- `proxy_to_worker` returns structured 503 (not 500) with `worker_url` in the body — matches the actionable-error contract from `AGENTS.md`.
- `bootstrap.validate_runtime_dependencies` runs at suite_api import and emits one consolidated error — end-user convenience compliant.
- `suite_api.main.lifespan` only inits the two stateful domains (neurohub Alembic, neurocnl job store/rate limiter); other domains stay stateless inside the monolith.
- `Module.fromJson` mirrors the manifest 1:1 (every JSON field is a Dart field, including the entire `launcherRuntime` subtree).

## Implementation plan (ordered)

### Wave 1 — Drift #5 (legacy config) + #6 (composeProfile) [verification only]
- `grep` for readers of `settings.{neurocnl,neurosim,neurochip,neurobench,neurosense,neurohub}_url` and `composeProfile` across `suite_api/`, `nmtk/`, `tests/`, `scripts/`.
- If zero live readers: remove the fields from `config.py` and `DeploymentCapability`.
- Update ADR 0018 to record the cleanup.

### Wave 2 — Drift #1 (manifest port contract)
- Define rule: `manifest.port` is the *deployment-mode* port (container/standalone); the in-process route base is always `settings.suite_api_port` (=9000).
- Add an integration test that asserts `manifest.port == settings.suite_api_port` for all `startStrategy == "none"` modules.
- Refactor `scripts/backend_endpoint_smoke.py::ModuleSpec.runnable` to also accept `startStrategy == "none"` modules whose `port == 9000` (in-process), probing `/api/suite/health/modules` and `/{module}/` static mount.
- Update `NmtkApiBaseUrl` Dart doc to make the consolidated `SUITE_API_URL` path the recommended default.

### Wave 3 — Drift #2 (test_cross_module.py)
- Rewrite to read a single `SUITE_API_URL` env var, default `http://localhost:9000`.
- Assert actual monolith shapes: `/api/neurocnl/parse` → 200, `/api/neurosim/...` etc.
- Cover the in-process pipeline: parse → validate → simulate → export within one suite_api process (no localhost hops).
- Run `python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py` as the gate per AGENTS.md.

### Wave 4 — Drift #7 (missing ADR 0001)
- Restore a stub `0001-module-manifest-system.md` recording the historical "one JSON manifest drives everything" decision, OR remove the reference from `nmtk/AGENTS.md`.

## Gate at end of each wave

- `bash scripts/run_launcher_guardrails.sh` for any launcher-touching change.
- `python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py` after Wave 3 onward.
- `python3 scripts/launcher_control_service.py --doctor --json` → `fatalCount == 0`.

## User decision log

- Focus: **Architecture & module contracts**
- Priority: **All of the above, ordered** (Drifts #1, #2, #5, #6, #7 in §6 order)
- Plan saved to: `tasks/11 june/architecture-contracts-deep-dive.md`

## References

- `nmtk/neuro_toolkit/assets/modules.json`
- `nmtk/neuro_toolkit/lib/models/module.dart`
- `nmtk/neuro_toolkit/lib/models/backend_deployment.dart`
- `nmtk_module_contracts/lib/src/*.dart`
- `suite_api/main.py`, `suite_api/config.py`, `suite_api/proxy.py`, `suite_api/bootstrap.py`
- `suite_api/domains/{neurocnl,neurosim,neurochip,neurobench,neurosense,neurohub,jupyter}/*`
- `suite_api/routers/health.py`
- `suite_api/middleware/__init__.py`
- `docs/ADR-claude/0001..0025/*.md` (0018, 0021, 0023 are the load-bearing ones)
- `docker-compose.yml`
- `tests/integration/test_cross_module.py`
- `scripts/{backend_endpoint_smoke.py,run_launcher_guardrails.sh,launcher_control_service.py}`
