# NeuroMorphicToolKit — Status Audit & Readiness Report

**Audit Date:** 01-Apr-2026
**Agent Assessor:** Codex
**Scope:** Root repository (cross-cutting analysis of root infrastructure and git submodules)
**Branch:** dev
**Context:** Executed at repository root with direct inspection, static-analysis runs, Flutter analysis, and Docker Compose validation

## 1. Executive Summary

**Overall POC Readiness: ~66%**.

This is a corrective restatement, not evidence of a one-day regression. The previous archive reports leaned heavily on file-presence inspection. This audit executed the configured tools and found that every Python submodule currently fails Ruff, every Python submodule fails or is blocked in `mypy --strict`, and 4 of the 6 submodule Flutter frontends fail `flutter analyze` with real errors.

**Major deltas since last run (31-Mar-2026):**

| Area | 31-Mar posture | 01-Apr evidence |
|---|---|---|
| Python quality | Partially improved | All 7 Python modules still fail Ruff; totals observed today: NDH 198, Neurobench 196, Neurochip 32, Neurohub 125, Neurosense 65, Neurosim 157, neurocnl 57 |
| Strict typing | Not re-run in prior audit | All 7 modules fail or are blocked in `mypy --strict`; Neurobench 105 errors, Neurochip 259, NDH 142, and three modules are stopped by packaging/layout issues before useful checking starts |
| Flutter readiness | Mostly inferred from file inspection | Only `nmtk_ui_core`, `nmtk/neuro_toolkit`, and `Neurochip/frontend` analyze clean; `Neurobench/frontend`, `Neurohub/frontend`, `Neurosense/frontend`, `Neurosim/frontend`, and `neurocnl/frontend` all report issues, with hard errors in Neurobench, Neurohub, and neurocnl |
| Backend completeness | Previously treated as broadly complete | Neurobench still exposes a 501 route on benchmark creation, Neurohub auth is structurally broken, and Neurosim’s sweep job API is only half-implemented |
| Docker/compose | Mostly presence-checked | Root and all submodule `docker-compose.yml` files are syntactically valid under `docker compose config --quiet`; 5 module compose files still use obsolete `version` keys |
| Task tracking | Previously counted as active work | The real system is fragmented archive-only tracking. Active `issues/` directories are empty; overlapping archive trees inflate the apparent remaining work |

**Most important blockers observed directly:**

1. Neurohub auth cannot be considered functional in its current form.
2. Neurobench benchmark execution contains a runtime `NameError` path and still ships a 501 benchmark-creation endpoint.
3. Neurosim’s sweep API exposes queued-job semantics but the background worker is a no-op.
4. neurocnl’s frontend and provider layer have enough type/analyzer errors to block a clean frontend release.
5. Python strict-typing claims are not credible anywhere in the workspace today.

## 2. Linter Snapshot

### Ruff

Executed directly in each Python module with `ruff check . --output-format concise`.

| Module | Result |
|---|---|
| Neuro-Dream-Hand | 198 errors |
| Neurobench | 196 errors |
| Neurochip | 32 errors |
| Neurohub | 125 errors |
| Neurosense | 65 errors |
| Neurosim | 157 errors |
| neurocnl | 57 errors |

**Observed pattern:** the workspace has moved past empty-file scaffolding in most modules, but code health is still inconsistent. Several Ruff hits are cosmetic, but today’s runs also surfaced real correctness problems such as undefined names, duplicated definitions, and malformed auth/model code.

### Mypy

Executed directly in each Python module with `mypy --strict .`.

| Module | Result |
|---|---|
| Neuro-Dream-Hand | 142 errors in 31 files |
| Neurobench | 105 errors in 21 files |
| Neurochip | 259 errors in 37 files |
| Neurohub | blocked immediately by missing `sqlalchemy` plugin import |
| Neurosense | blocked by duplicate module discovery from committed `build/lib/neurosense` tree |
| Neurosim | blocked by duplicate module discovery from committed `build/lib/neurosim` tree |
| neurocnl | blocked by package-layout duplication (`app.schemas.prosthetic` vs `backend.app.schemas.prosthetic`) |

**Takeaway:** no module can currently claim strict-type readiness. In three modules the packaging/layout is preventing meaningful strict checking at all.

### Flutter Analyze

Executed with `flutter analyze` in root Flutter packages and every submodule frontend package.

| Package | Result |
|---|---|
| `nmtk_ui_core` | clean |
| `nmtk/neuro_toolkit` | clean |
| `Neurochip/frontend` | clean |
| `Neurobench/frontend` | 13 issues, including hard type errors |
| `Neurohub/frontend` | 14 issues, including missing dependency/URI and failing tests |
| `Neurosense/frontend` | 1 warning (`path` dependency) |
| `Neurosim/frontend` | 10 issues, mostly warnings/info plus dependency hygiene |
| `neurocnl/frontend` | 97 issues, including provider/model type errors and broken tests |

## 3. Task Fragmentation Findings

### What is actually active

- Root `issues/` is empty.
- `nmtk/issues` is empty.
- Module-local `issues/` directories checked in Neurobench, Neurohub, Neurosim, Neurosense, and neurocnl are empty.
- The real tracking load lives in `issues-archive/` folders plus the root archive trees under `docs/`, `nmtk/`, and `nmtk/neuro_toolkit/`.

### Fragmentation patterns

The same workstreams are repeatedly re-archived under different module folders and root archive trees:

- `add-agents-md-and-guardrails-md`
- `add-cors-middleware`
- `rate-limiting`
- `authentication-layer`
- `structured-logging`
- `security-md-and-changelog-md`
- `container-hardening`
- `end-to-end-integration-tests`

There are also within-repo duplicates that make the true backlog harder to read:

- Neurobench has both `002-poc-add-agents-md-and-guardrails-md.md` and `005-poc-add-agents-md-and-guardrails-md.md`.
- Neurohub has both `003-poc-add-agents-md-and-guardrails-md.md` and `005-poc-add-agents-md-and-guardrails-md.md`.
- Neurosim has both `003-poc-add-agents-md-and-guardrails-md.md` and `006-poc-add-agents-md-and-guardrails-md.md`.
- Neurosense has both `002-poc-add-agents-md-and-guardrails-md.md` and `005-poc-add-agents-md-and-guardrails-md.md`.
- `nmtk/issues-archive` reuses numeric prefixes (`003`, `004`, `009`) for unrelated tasks, making simple counts misleading.

### Recommended deprecations

- Treat empty `issues/` directories as non-canonical until they are repopulated.
- Deprecate root-level duplicate archive trees as planning sources. The least ambiguous canonical units today are the module-local `issues-archive/` folders plus `nmtk/neuro_toolkit/issues-archive` for launcher work.
- Stop counting repeated cross-cutting issue titles as separate remaining work unless they map to different modules with different code owners.

### True remaining-task picture

The apparent backlog is inflated by archive duplication. The real remaining work is not “hundreds of issue files”; it is a smaller set of recurring cross-module tracks:

- backend correctness and contract completion
- frontend analyzer/test cleanup
- Python strict-type and package-layout repair
- real integration coverage in place of mock-heavy suites
- packaging/compose/CI hardening

## 4. Target Readiness & Module Status

### Root workspace / launcher — ~80%

| Area | Status |
|---|---|
| Backend/infra | root compose validates cleanly; launcher Flutter package analyzes cleanly |
| Frontend | `nmtk/neuro_toolkit` and `nmtk_ui_core` both analyze clean |
| Tests | root launcher has 15 Dart tests; `nmtk_ui_core` has 9 |
| Docker | root `docker compose config --quiet` passes |
| CI | 34 root workflows exist, but no live workflow run was re-verified in this audit |

### neurocnl — ~72%

| Area | Status |
|---|---|
| Backend | substantial implementation: multi-router FastAPI app, prosthetic subrouters, job store, metrics, auth/rate-limit middleware |
| Frontend | substantial UI exists, but `flutter analyze` reports 97 issues including provider/model typing failures |
| Tests | 56 Python tests and 11 Dart tests; includes genuine browser/server E2E (`tests/e2e/test_production_pipeline.py`) |
| Contracts | broad parser/generator/export surface appears implemented |
| Docker | `backend/Dockerfile`, `frontend/Dockerfile`, and compose file all present; compose validates with obsolete `version` warning |
| CI | module workflows exist |

### Neuro-Dream-Hand — ~74%

| Area | Status |
|---|---|
| Backend/library | large, real Python research codebase; not a stubbed module |
| Frontend | none |
| Tests | 38 Python tests with at least 2 property-style tests |
| Contracts | hardware and experiment contract surface exists |
| Docker | Dockerfile and compose present; compose validates with obsolete `version` warning |
| CI | 11 workflows present |

### Neurochip — ~82%

| Area | Status |
|---|---|
| Backend | implementation is broad and more coherent than most peers |
| Frontend | `flutter analyze` clean |
| Tests | 29 Python tests, 6 Dart tests, 4 property-style files |
| Contracts | estimation, deployment, quantization, and target contracts present |
| Docker | Dockerfile and compose present; compose validates with obsolete `version` warning |
| CI | module workflows exist |

### Neurosense — ~70%

| Area | Status |
|---|---|
| Backend | real device, filter, recording, and stream code exists |
| Frontend | mostly healthy; `flutter analyze` reports only 1 package-hygiene warning |
| Tests | 28 Python tests, 12 Dart tests, 4 property-style files |
| Contracts | signal, recording, encoding, and device contracts present |
| Docker | backend and frontend Dockerfiles plus compose file; compose validates with obsolete `version` warning |
| CI | module workflows exist |

**Caveat:** strict typing is not currently trustworthy because committed `build/lib/neurosense` duplicates the importable package and blocks mypy before useful checking begins.

### Neurosim — ~62%

| Area | Status |
|---|---|
| Backend | broad route/service surface exists, but the sweep-job flow is only partially implemented |
| Frontend | real screens/widgets exist; analyze returns 10 issues, mostly non-fatal but still unresolved |
| Tests | 28 Python tests, 6 Dart tests, 2 property-style files |
| Contracts | present but lighter than the strongest modules |
| Docker | backend and frontend Dockerfiles plus compose file; compose validates with obsolete `version` warning |
| CI | module workflows exist |

**Caveat:** committed `build/lib/neurosim` duplicates the package and blocks mypy.

### Neurobench — ~58%

| Area | Status |
|---|---|
| Backend | broad router/service surface exists, but there are still concrete runtime and endpoint-completeness defects |
| Frontend | `flutter analyze` reports 13 issues, including broken `BaselineSelector` typing and failing tests |
| Tests | 27 Python tests, 9 Dart tests, 5 property-style files |
| Contracts | benchmark/regression/report contracts exist |
| Docker | Dockerfile and compose file present; compose validates cleanly |
| CI | module workflows exist |

**Caveat:** several tests are mock-heavy (`tests/test_service_stubs.py`), so file count overstates real benchmark/hardware coverage.

### Neurohub — ~52%

| Area | Status |
|---|---|
| Backend | project/activity/workflow/auth surface exists, but auth is not in a releasable state |
| Frontend | `flutter analyze` reports 14 issues, including a missing `url_launcher` dependency and broken tests |
| Tests | 31 Python tests, 23 Dart tests, 5 property-style files |
| Contracts | project/bundle/workflow contract files exist |
| Docker | backend and frontend Dockerfiles plus compose file; compose validates cleanly |
| CI | module workflows exist |

**Caveat:** test count overstates integration confidence because part of the suite is driven by a mocked orchestration server (`tests/mock_suite_server.py`).

## 5. Priority Work Roadmap

### P0 (Critical)

- Repair Neurohub authentication end-to-end: remove recursive/duplicate `User` properties, stop referencing undefined API-key globals, and run both backend and frontend tests against the real auth flow.
- Fix Neurobench benchmark execution correctness: define/import `SpikeFidelityError` properly and replace the 501 benchmark-creation route with a real implementation or remove it from the exposed API surface.
- Finish or redesign Neurosim sweep jobs: either implement `run_sweep_sync` plus queued job persistence, or simplify the API to a synchronous sweep endpoint and drop the fake job lifecycle.
- Make `neurocnl/frontend` analyzable: clean the provider/model typing errors and repair the currently broken tests before calling the Studio frontend release-ready.

### P1 (Core Integration)

- Make `mypy --strict` meaningful again in Neurohub, Neurosense, Neurosim, and neurocnl by fixing plugin/dependency setup and removing committed duplicate package trees from type-check paths.
- Bring all Python modules to a stable Ruff baseline, prioritizing correctness-class findings before style-only cleanup.
- Replace mock-dominated test paths with at least one real happy-path integration run per major module: Neurobench benchmark execution, Neurohub orchestration, Neurosim sweep/export, and Neurosense streaming/export.
- Normalize Flutter dependency health across submodule frontends, especially missing dependencies in Neurohub and broken model/provider usage in Neurobench and neurocnl.

### P2 (Polish/Quality)

- Remove obsolete `version` keys from module compose files to eliminate noise in compose validation.
- Collapse issue tracking onto a canonical system and stop duplicating archived work under multiple root trees.
- Tighten CI so status audits can rely on fresh machine-generated signals instead of mixed archive history and manual interpretation.
- Reduce test-suite false confidence by separating fully mocked contract tests from real integration smoke tests in reporting.
