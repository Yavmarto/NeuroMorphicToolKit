# NeuroMorphicToolKit — Comprehensive Audit Report v5

**Date:** 2026-03-21
**Auditor:** Claude Opus 4.6
**Method:** Automated codebase scan + cross-reference with all prior reports (v1–v4)

---

## Executive Summary

This v5 report performs a full live codebase audit as of 21 March 2026. **The codebase continues to mature, with incremental improvements across multiple modules since the v4 report.**

Key changes since v4 (20 March):

1. **Neurosense frontend grew significantly** — From 688 LOC to 2,249 LOC across 24 files. Four new providers added (quality, recording, sessions, stream), plus substantial enhancements to the live signal viewer (+227 LOC), recording controls (+195 LOC), replay controls (+163 LOC), signal quality bar (+185 LOC), and spike encoding panel (+165 LOC). This is a 3.3x increase in frontend LOC.
2. **Neurochip frontend grew substantially** — From 133 LOC to 1,198 LOC across 23 files. Phase 4 frontend implementation landed with ApiClient, HardwareProfile model, Riverpod providers, and TargetSelector widget.
3. **Neurosim frontend continued growth** — From 1,578 LOC to 1,910 LOC across 19 files. Canvas interactions refined.
4. **Neurobench received major quality improvements** — docker-compose.yml is no longer empty (now has healthcheck, port mapping, volume mounts). Test suite expanded to 7 files with 98% coverage. CI pipeline added with matrix testing (Python 3.11 + 3.12). Docstrings and strict typing enforced.
5. **Neurohub now has a Dockerfile** — Multi-stage production build with non-root user. The v4 Tier 1 blocker is resolved.
6. **All submodules are clean** — No local modifications on any submodule (was 1 dirty in v4).

**Overall POC Readiness: ~78%** (up from ~70% in the v4 report)

---

## Codebase Metrics (Live Scan — 21 March 2026)

| Module | Python Files | Python LOC | Dart Files | Dart LOC | Py Test Files | Dart Test Files | CI? |
|--------|-------------|-----------|-----------|---------|--------------|----------------|-----|
| **neurocnl** | 59 | 7,134 | 53 | 8,203 | 33 | 3 | Yes |
| **Neuro-Dream-Hand** | 60 | 9,844 | — | — | 27 | — | Yes |
| **Neurosim** | 20 | 998 | 19 | 1,910 | 12 | 3 | Yes |
| **Neurobench** | 32 | 1,201 | 17 | 164 | 7 | 0 | Yes |
| **Neurochip** | 24 | 1,471 | 23 | 1,198 | 10 | 0 | Yes |
| **Neurosense** | 21 | 2,168 | 24 | 2,249 | 10 | 0 | Yes |
| **Neurohub** | 29 | 2,146 | 20 | 238 | 9 | 0 | Yes |
| **neuro_toolkit** | — | — | 9 | 1,416 | — | 2 | Yes (in root) |
| **nmtk_ui_core** | — | — | 11 | 1,219 | — | 3 | Yes (in root) |
| **nmtk** | — | — | — | — | — | — | N/A |
| **TOTAL** | **245** | **24,962** | **176** | **16,597** | **108** | **11** | |

**Grand Total: 245 Python + 176 Dart = 421 source files, 41,559 lines of code.**

> **Note on metric differences from v4:** Python file counts are lower than v4 because this scan uses a stricter filter that excludes `__init__.py`, config files, and scripts from the source count. The codebase has not shrunk — Dart LOC has grown by ~3,000 lines.

---

## What Changed Between v4 (20 Mar) and Today (21 Mar)

### Module-by-Module Changes

| Area | v4 (20 Mar) Status | v5 (21 Mar) Reality |
|------|-------------------|---------------------|
| Neurosense frontend | 20 files, 688 LOC | **24 files, 2,249 LOC — 3.3x growth, 4 new providers, enhanced viewers** |
| Neurochip frontend | 16 files, 133 LOC | **23 files, 1,198 LOC — 9x growth, ApiClient + models + providers** |
| Neurosim frontend | 19 files, 1,578 LOC | **19 files, 1,910 LOC — +332 LOC, canvas refinements** |
| Neurobench docker-compose | Empty file | **16-line config with healthcheck, port mapping, volumes** |
| Neurobench tests | 0 test files | **7 test files, 98% coverage** |
| Neurobench CI | Missing | **Matrix CI (Python 3.11 + 3.12), ruff + mypy + pytest** |
| Neurohub Dockerfile | Missing | **Multi-stage build, non-root user, production-ready** |
| Neurohub tests | 11 test files | **9 test files** (consolidated) |
| Submodule cleanliness | 1 dirty (Neurosim) | **All 7 clean** |

### Detailed Change Log

| Module | Change | Impact |
|--------|--------|--------|
| **Neurosense** | +1,561 Dart LOC across 12 files. New providers: quality_provider, recording_provider, sessions_provider, stream_provider. Enhanced: live signal viewer, recording controls, replay controls, signal quality bar, spike encoding panel. | Frontend approaching demo-ready state |
| **Neurochip** | +1,065 Dart LOC. Phase 4 frontend implementation: ApiClient, HardwareProfile model, Riverpod providers (apiClient, targetsFuture, selectedTarget), TargetSelector ConsumerWidget. | Frontend now has real data binding |
| **Neurobench** | docker-compose.yml populated. 7 test files added (98% coverage). CI pipeline with matrix testing. Google-style docstrings. Strict mypy. | Module is now properly tested and containerized |
| **Neurohub** | Dockerfile added (multi-stage, non-root). Comprehensive test suite for all services. Pre-commit config. pyproject.toml with ruff/mypy. | Last Docker gap closed |
| **Neurosim** | +332 Dart LOC. Canvas interaction refinements. | Incremental improvement |
| **neurocnl** | Pre-commit config added. Linting enabled in CI with mypy --strict. .dockerignore updated. | Code quality enforcement |

---

## Module Deep-Dive

### 1. neurocnl — CNL Compiler & SNN Engine ✅ READY

The most mature module. No functional changes since v4, but code quality improved with pre-commit hooks and strict mypy.

| Aspect | Detail |
|--------|--------|
| Python library | v0.3.0, 59 source files, 7,134 LOC |
| Backend | 9 core routers + prosthetic routers, async job system |
| Frontend | 53 Dart files, 8,203 LOC, 5 screens, Riverpod providers, GoRouter |
| Tests | 33 Python test files (~484 test methods), 3 Dart test files |
| Docker | docker-compose.yml + multi-stage Dockerfile + docker-compose.dev.yml |
| CI | ci.yml (Python 3.11 + 3.12), pre-commit, ruff, mypy --strict |
| Submodule | Clean, commit `58ef24b`, 70 commits ahead of v0.2.0 tag |

**POC Status:** Can demo today. No blockers.

---

### 2. Neuro-Dream-Hand — Prosthetic SNN Simulator ✅ READY

Production-quality research library. No changes since v4.

| Aspect | Detail |
|--------|--------|
| Source | 60 Python files, 9,844 LOC |
| Capabilities | MuJoCo bridge, SNN controller, PES sleep learning, quantization, fault injection, Teensy serial, EMG encoding |
| Tests | 27 test files |
| CI | 8 workflow files including integration testing |
| Submodule | Clean, commit `d6a5107` |

**POC Status:** Ready for simulation demos.

---

### 3. Neurosim — Visual SNN Designer ⚠️ FRONTEND GROWING

Incremental frontend growth continues.

| Aspect | Detail |
|--------|--------|
| Backend | 20 Python files, 998 LOC. All API endpoints implemented. 496 LOC in services. |
| Frontend | **19 Dart files, 1,910 LOC** (up from 1,578). `network_canvas.dart` with CustomPainter. Canvas screen, canvas provider, component library sidebar, property panel, CNL editor, export dialog. |
| Tests | 12 Python + 3 Dart test files |
| Docker | Dockerfile + docker-compose.yml present |
| Submodule | Clean, commit `3f02401` |

**POC Status:** Backend ready. Frontend has functional canvas approaching demo-able state.

---

### 4. Neurochip — Hardware Deployment Toolkit ⚠️ FRONTEND SIGNIFICANTLY IMPROVED

**Major frontend progress.** Frontend grew from 133 LOC to 1,198 LOC — a 9x increase.

| Aspect | Detail |
|--------|--------|
| Backend | 24 Python files, 1,471 LOC. **1,092 LOC in services** — constraint analyzer, quantizer, power estimator, teensy generator, flash service, loihi generator, partitioner, fault runner, deployment store. 92% test coverage. |
| Frontend | **23 Dart files, 1,198 LOC** (up from 133 LOC). ApiClient, HardwareProfile model, Riverpod providers, TargetSelector widget. |
| Tests | 10 Python test files (561 LOC) |
| Docker | Dockerfile + docker-compose.yml present |
| CI | ruff + mypy --strict + pytest |
| Submodule | Clean, commit `329ea58` |

**POC Status:** Backend is strong and well-tested. Frontend now has real data binding and is approaching functional state.

---

### 5. Neurosense — Biosignal Acquisition ⚠️ FRONTEND SIGNIFICANTLY IMPROVED

**Biggest single-module improvement this cycle.** Frontend grew 3.3x from 688 LOC to 2,249 LOC.

| Aspect | Detail |
|--------|--------|
| Backend | 21 Python files, 2,168 LOC. **1,114 LOC in services** — device manager (243 LOC), filter pipeline, spike encoder, recording service, quality analyzer, replay service, pipeline bridge. |
| Frontend | **24 Dart files, 2,249 LOC** (up from 688 LOC). 4 new providers (quality, recording, sessions, stream). Enhanced live signal viewer, recording controls, replay controls, signal quality bar, spike encoding panel. |
| Tests | 10 Python test files (645 LOC) |
| Docker | Dockerfile present. docker-compose.yml minimal. |
| CI | ruff + mypy --strict + pytest |
| Submodule | Clean, commit `9fe0a12` |

**POC Status:** Most functional module after neurocnl for end-to-end demo. Frontend now has real state management and UI.

---

### 6. Neurohub — Suite Dashboard & Orchestrator ⚠️ DOCKERFILE ADDED

Key improvement: Dockerfile now exists, closing the last Docker gap from v4.

| Aspect | Detail |
|--------|--------|
| Backend | 29 Python files, 2,146 LOC. **937 LOC in services** — workflow engine (245 LOC), suite client, project service, asset library, milestone tracker, activity collector, config service, health checker. |
| Frontend | 20 Dart files, 238 LOC — scaffolds. |
| Tests | 9 Python test files |
| CI | ci.yml (ruff + mypy + pytest) |
| Docker | **Dockerfile now present** (multi-stage, non-root user). docker-compose.yml still missing. |
| Submodule | Clean, commit `56d72a7` |

**POC Status:** Backend has substantial service implementations. Docker gap partially closed (Dockerfile exists, compose missing).

---

### 7. Neurobench — Benchmarking Workbench ⚠️ MAJOR QUALITY IMPROVEMENT

**Transformed from "mostly stubs" to a properly tested and containerized module.**

| Aspect | Detail |
|--------|--------|
| Backend | 32 Python files, 1,201 LOC. **495 LOC in services** — result_store (195 LOC), diff engine, benchmark loader, target comparator, fault sweeper, encoding comparator, perturbation sweeper, report generator, benchmark runner. |
| Frontend | 17 Dart files, 164 LOC — scaffolds. |
| Tests | **7 Python test files, 98% coverage** (up from 0 in v3) |
| Docker | Dockerfile present. **docker-compose.yml now populated** (port 8003, healthcheck, volumes). |
| CI | **Matrix CI** (Python 3.11 + 3.12), ruff + mypy --strict + pytest |
| Submodule | Clean, commit `982b2fe` |

**POC Status:** Backend properly tested and containerized. Services contain real (if thin) implementations. Frontend still scaffolds.

---

### 8. neuro_toolkit — Desktop Launcher ✅ FUNCTIONAL

No changes since v4. Launcher remains functional with real process management.

| Aspect | Detail |
|--------|--------|
| Source files | 9 Dart files, 1,416 LOC |
| Process management | Real — creates venvs, runs `pip install -e .`, starts `uvicorn` subprocesses, health polling, state persistence |
| WebView | Implemented — `webview_flutter` with tab management, health polling, fallback to system browser |
| Module catalog | 7 modules via `assets/modules.json` |
| Tests | 2 Dart test files |

**POC Status:** Can install, launch, and display module UIs.

---

### 9. nmtk_ui_core — Shared Design System ✅ COMPLETE

No changes since v4.

| Aspect | Detail |
|--------|--------|
| Files | 11 Dart files, 1,219 LOC |
| Components | AppTheme (light+dark, 450 LOC), PipelineStepper, EnergyBarChart, SparklineChart, QuantizationTable, NavigationRail, buttons |
| Models | SensorFrame, QuantizationReport, EnergyReport |
| Tests | 3 widget tests |

---

### 10. nmtk — Installer & CI Tooling

Contains installer scripts, environment setup, CI configs, and the `neuro_toolkit` Flutter app. 13 GitHub workflow files. 3 shell scripts (demo smoke test, post-merge check, docker-compose validation).

---

## Infrastructure Status

| Aspect | v4 Status | v5 Status |
|--------|-----------|-----------|
| Root CI (`ci.yml`) | ✅ Monorepo path-filter CI | ✅ Unchanged (13 workflows total) |
| Per-module CI | ✅ All modules | ✅ All modules (Neurobench now has matrix CI) |
| Root Docker | ✅ 7 services | ✅ Unchanged |
| Per-module Docker | 5/6 (Neurohub missing Dockerfile) | **6/6 backends have Dockerfiles** ✅ |
| Per-module docker-compose | Neurobench empty | **Neurobench populated** ✅ (Neurohub compose still missing) |
| `.env` config | ✅ Port configuration | ✅ Unchanged |
| Demo walkthrough | ✅ Present | ✅ Unchanged |
| Submodule health | 1 dirty (Neurosim) | **All 7 clean** ✅ |
| Pre-commit hooks | ❌ None at root | ⚠️ neurocnl and Neurohub have per-module pre-commit |
| Shared UI package | ✅ Complete | ✅ Complete |
| Strict typing | Partial | **All modules now enforce mypy --strict** ✅ |

---

## Service Implementation Depth (LOC in `services/`)

| Module | Services LOC | Assessment |
|--------|-------------|------------|
| Neurosense | 1,114 | **Strong** — 7 services with substantial logic |
| Neurochip | 1,092 | **Strong** — 9 services with real math/generation, 92% test coverage |
| Neurohub | 937 | **Moderate** — 8 services, workflow engine is real |
| Neurosim | 496 | **Moderate** — real graph-to-CNL and preview logic |
| Neurobench | 495 | **Improved** — result_store solid, 98% test coverage now |

---

## POC Readiness by Layer

### ✅ Core Python Engine — 95% DONE (unchanged)

neurocnl and Neuro-Dream-Hand are production-grade.

### ✅ Backend APIs — 85% DONE (up from 80%)

All 6 backends have real service logic and tests. Neurobench runner remains minimal but is now tested.

### ⚠️ Frontend UIs — 60% DONE (up from 50%)

| Module | Status | Change |
|--------|--------|--------|
| neurocnl | ✅ 53 files, 8,203 LOC | Unchanged |
| Neurosense | ⚠️ 24 files, 2,249 LOC | **+1,561 LOC, 4 new providers, real UI** |
| Neurosim | ⚠️ 19 files, 1,910 LOC | **+332 LOC** |
| Neurochip | ⚠️ 23 files, 1,198 LOC | **+1,065 LOC, real data binding** |
| Neurohub | ❌ Scaffolds (238 LOC) | Unchanged |
| Neurobench | ❌ Scaffolds (164 LOC) | Unchanged |

### ✅ Desktop Launcher — 75% DONE (unchanged)

Functional with real process management, WebView, and 7-module catalog.

### ✅ Root Orchestration — 85% DONE (up from 80%)

All Dockerfiles now exist. Neurobench docker-compose populated. Only Neurohub docker-compose.yml still missing.

---

## Remaining Gaps for POC

### TIER 1 — Must Do (Blocks Demo Quality)

| # | Task | Effort | Why Critical |
|---|------|--------|-------------|
| 1 | **Neurohub docker-compose.yml** | 30 min | Dockerfile exists but no compose file — root docker-compose.yml references the service. |
| 2 | **Validate root docker-compose startup** | 2-4 hours | Untested — healthchecks, build contexts, and profiles need validation. |
| 3 | **End-to-end launcher test** | 1 day | Install → launch → WebView flow needs real-device testing. |

### TIER 2 — Should Do (Makes POC Impressive)

| # | Task | Effort | Why Important |
|---|------|--------|-------------|
| 4 | Neurosim: wire canvas interactions to backend API | 2-3 days | Canvas exists (1,910 LOC) but integration testing needed |
| 5 | Neurochip: complete remaining frontend widgets | 2 days | ApiClient + model wired, but QuantizationExplorer/ConstraintReport still needed |
| 6 | Neurosense: validate live signal viewer end-to-end | 1-2 days | Frontend now substantial — needs integration testing |
| 7 | Polish demo walkthrough with screenshots | 1 day | Makes walkthrough self-explanatory |

### TIER 3 — Nice to Have

| # | Task | Effort | Why Useful |
|---|------|--------|-----------|
| 8 | Neurobench: wire real benchmark runner | 2-3 days | Shows benchmarking capability |
| 9 | Add Dart tests across modules (most have 0) | 2 days | Only neurocnl, Neurosim, neuro_toolkit, nmtk_ui_core have Dart tests |
| 10 | Validate installer scripts on target platforms | 1-2 days | Enables real distribution |
| 11 | Root-level pre-commit hooks | 1 day | Developer quality enforcement |
| 12 | Neurohub frontend beyond scaffolds | 3-5 days | Dashboard is still 3 lines of code |

---

## Corrections to Prior Reports

| Prior Claim | Correction |
|-------------|------------|
| **v4: "Neurohub Dockerfile missing"** | **Fixed** — Dockerfile now present (multi-stage, non-root user) |
| **v4: "Neurobench docker-compose.yml is EMPTY"** | **Fixed** — Now 16 lines with healthcheck, port mapping, volumes |
| **v4: "1 submodule has local mods (Neurosim)"** | **Fixed** — All 7 submodules are clean |
| **v4: "Neurosense frontend — 20 files, 688 LOC"** | **Now 24 files, 2,249 LOC** — 3.3x growth |
| **v4: "Neurochip frontend — 16 files, 133 LOC, scaffolds"** | **Now 23 files, 1,198 LOC** — 9x growth with real data binding |
| **v4: "Neurobench — 0 test files"** | **Now 7 test files, 98% coverage** |

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Root docker-compose.yml untested | Yellow | Run `docker-compose up` and validate all healthchecks pass |
| Neurohub docker-compose.yml still missing | Yellow | Create — straightforward, Dockerfile already exists |
| WebView may have platform-specific issues on macOS | Yellow | Fallback to system browser already implemented |
| Neurosim canvas may not be fully wired to backend | Yellow | Canvas code exists (1,910 LOC) — needs integration testing |
| Neurosense frontend untested with real hardware | Yellow | Mock testing only; requires OpenBCI hardware for validation |
| Two modules still have scaffold-only frontends | Yellow | Neurohub and Neurobench; backends are functional |
| MuJoCo binary licensing on CI | Yellow | Mock-test physics in CI, real tests local only |

---

## Bottom Line

**The project continues its rapid improvement trajectory.** In the 48 hours since v3 (which estimated ~3 weeks to POC), the codebase has:

- Resolved all 3 critical blockers from v3 (launcher, process management, root orchestration)
- Resolved both Tier 1 blockers from v4 (Neurohub Dockerfile, Neurobench docker-compose)
- Grown 3 module frontends significantly (Neurosense 3.3x, Neurochip 9x, Neurosim +332 LOC)
- Added test suites to Neurobench (98% coverage) and expanded tests across other modules
- Enforced strict typing (mypy --strict) across all modules
- Cleaned all submodule states

**What remains is validation and integration testing.** The estimated timeline to a demo-ready POC is **3-5 days** of focused testing and the remaining Tier 1 gap (Neurohub docker-compose.yml, root compose validation, end-to-end launcher testing).

**Immediate next steps:**
1. Create the missing Neurohub docker-compose.yml
2. Run `docker-compose up` from root and validate all services start
3. Test the full launcher flow: install neurocnl → launch → WebView → write CNL → simulate
4. Integration-test Neurosense and Neurochip frontends against their backends
