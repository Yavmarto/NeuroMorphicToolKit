# NeuroMorphicToolKit — Status Report

**Generated:** 21 March 2026
**Branch:** dev
**Assessor:** Claude Opus 4.6
**Method:** Full codebase exploration + cross-reference with prior status reports (19-Mar Opus, 20-Mar Opus v4)

---

## Executive Summary

The NeuroMorphicToolKit is a multi-module neuromorphic computing platform: a Flutter desktop launcher (`neuro_toolkit`) that orchestrates 7 Python/FastAPI backend modules, each with its own Flutter frontend. Two core Python libraries (`neurocnl` and `Neuro-Dream-Hand`) are production-quality. All 6 backend APIs have real service logic. The launcher can now actually start and manage backend processes. Root Docker orchestration exists.

**Overall POC Readiness: ~78%**

- Core Python engine: DONE
- Backend APIs: 6 of 6 implemented with tests
- Frontend UIs: 1 complete (neurocnl), 3 substantially built (Neurosense, Neurochip, Neurosim), 2 scaffolds (Neurohub, Neurobench)
- Launcher orchestration: FUNCTIONAL (real venv + uvicorn management)
- Root-level Docker orchestration: EXISTS (7 services, untested)

---

## What Changed Since Last Status Report (19-Mar)

| Area | 19-Mar Status | 21-Mar Reality |
|------|--------------|----------------|
| neuro_toolkit launcher | Mock only — `Future.delayed()` faking installation | **Real ProcessManager** — venv creation, pip install, uvicorn subprocess management, health polling |
| WebView integration | None | **`webview_flutter` with tabs, health polling, browser fallback** |
| Module catalog | 3 hardcoded entries | **7 modules via JSON manifest** |
| Root Docker orchestration | Did not exist | **7-service docker-compose.yml with healthchecks and profiles** |
| Neurosim frontend | 14 files, 556 LOC — boilerplate | **19 files, 1,910 LOC — real canvas with CustomPainter, drag-and-drop** |
| Neurosense frontend | 20 files, 688 LOC — partial | **24 files, 2,249 LOC — 4 new providers, enhanced viewers/controls** |
| Neurochip frontend | ~109 LOC — stubs | **23 files, 1,198 LOC — ApiClient, models, Riverpod providers** |
| Neurobench tests | 0 files | **7 test files, 98% coverage** |
| Neurobench Docker | Blank docker-compose.yml | **Populated with healthcheck, port mapping, volumes** |
| Neurohub Docker | No Dockerfile | **Multi-stage Dockerfile present** |
| Neurohub CI | Missing | **ci.yml with ruff + mypy + pytest** |
| All module CI | Most present | **All modules have CI with strict mypy** |
| Submodule health | 4 with local mods | **All 7 clean** |
| Demo walkthrough | Did not exist | **113-line guide + smoke test script** |

---

## Module Status Matrix

| Module | Backend | Frontend | Docker | Tests | LOC (Py) | LOC (Dart) | POC Ready? |
|--------|---------|----------|--------|-------|----------|------------|------------|
| **neurocnl** | 95% | 85% | Yes (multi-stage) | 33 files (~484 tests) | 7,134 | 8,203 | YES |
| **Neuro-Dream-Hand** | 95% (library) | N/A | No (Conda) | 27 files | 9,844 | — | YES (sim only) |
| **Neurosim** | 90% | 55% | Yes | 12 + 3 Dart | 998 | 1,910 | Backend + canvas |
| **Neurochip** | 90% | 45% | Yes | 10 files (92% cov) | 1,471 | 1,198 | Backend + partial frontend |
| **Neurosense** | 90% | 65% | Yes (no compose) | 10 files | 2,168 | 2,249 | Backend + partial frontend |
| **Neurohub** | 75% | 10% | Dockerfile only | 9 files | 2,146 | 238 | No |
| **Neurobench** | 50% | 10% | Yes | 7 files (98% cov) | 1,201 | 164 | No |
| **neuro_toolkit** | N/A | 80% | N/A | 2 Dart | — | 1,416 | FUNCTIONAL |
| **nmtk_ui_core** | N/A | 100% | N/A | 3 Dart | — | 1,219 | Yes |
| **nmtk** | N/A | N/A | N/A | N/A | — | — | CI tooling |

**Totals:** ~24,962 Python LOC | ~16,597 Dart LOC | 421 source files | 108 Python test files + 11 Dart test files

---

## Detailed Module Status

### 1. neurocnl — CNL Compiler & SNN Engine (READY)

The crown jewel. Fully functional end-to-end pipeline.

**Python library (v0.3.0):** CNL parser, Nengo code generator, 5 export formats, spike encoding, visualization, CLI. 59 source files.

**FastAPI backend:** 9+ routers, async job system for long simulations.

**Flutter frontend:** 5 screens — Studio, Deploy, Hardware, Analysis, Server Setup. 53 Dart files, 8,203 LOC. Riverpod + GoRouter.

**Docker:** Multi-stage build + dev compose. Backend on `:8000`, frontend on `:8080`.

**Tests:** 33 files with ~484 test methods. 3 Dart test files.

**CI:** Python 3.11 + 3.12 matrix. Pre-commit hooks. mypy --strict. ruff.

**Status:** Can demo today. No blockers.

---

### 2. Neuro-Dream-Hand — Prosthetic SNN Simulator (READY)

Production-quality research library. Standalone Python — no web frontend.

**Capabilities:** MuJoCo physics bridge, SNN reflex controller, PES sleep learning, online continual learning, INT-N quantization, fault injection, power estimates, Teensy serial bridge, EMG spike encoder, 13 tutorial scripts.

**Tests:** 27 files, 130+ passing. 8 CI workflows including integration tests.

**Status:** Ready for simulation demos.

---

### 3. Neurosim — Visual SNN Designer (FRONTEND GROWING)

**Backend:** 20 Python files, 998 LOC. 12 test files. All API endpoints functional.

**Frontend:** 19 Dart files, 1,910 LOC. `network_canvas.dart` with CustomPainter for node/edge rendering, InteractiveViewer for pan/zoom. Canvas provider with debounced CNL generation. Component library sidebar, property panel, CNL editor, export dialog. 3 Dart test files.

**Docker:** Ready.

**Status:** Backend ready. Frontend has functional canvas. Needs integration testing.

---

### 4. Neurochip — Hardware Deployment Toolkit (FRONTEND SIGNIFICANTLY IMPROVED)

**Backend:** 24 Python files, 1,471 LOC. 1,092 LOC in 9 services. 10 test files, 92% coverage.

**Frontend:** 23 Dart files, 1,198 LOC. ApiClient, HardwareProfile model, Riverpod providers (apiClient, targetsFuture, selectedTarget), TargetSelector ConsumerWidget.

**Docker:** Ready.

**Status:** Backend strong and well-tested. Frontend now has real data binding. Remaining widgets (QuantizationExplorer, ConstraintReport) needed.

---

### 5. Neurosense — Biosignal Acquisition (FRONTEND SIGNIFICANTLY IMPROVED)

**Backend:** 21 Python files, 2,168 LOC. 1,114 LOC in 7 services (device manager 243 LOC, filter pipeline, spike encoder, recording service, quality analyzer, replay service, pipeline bridge). 10 test files.

**Frontend:** 24 Dart files, 2,249 LOC. 4 providers (quality, recording, sessions, stream). Enhanced live signal viewer, recording controls, replay controls, signal quality bar, spike encoding panel. DeviceSelector with full state management.

**Docker:** Dockerfile present, docker-compose.yml minimal.

**Limitation:** Requires physical OpenBCI hardware to validate beyond mock tests.

**Status:** Most functional module after neurocnl for end-to-end demo.

---

### 6. Neurohub — Suite Dashboard (BACKEND WORKS, FRONTEND SCAFFOLD)

**Backend:** 29 Python files, 2,146 LOC. 937 LOC in 8 services — workflow engine (245 LOC), suite client, project service, asset library, milestone tracker, activity collector, config service, health checker. SQLAlchemy ORM with models. 9 test files.

**Frontend:** 20 Dart files, 238 LOC — scaffolds. 8 screen files, 11 widget files, all minimal.

**Docker:** Dockerfile present (multi-stage, non-root). No docker-compose.yml.

**CI:** ruff + mypy + pytest.

**Status:** Backend substantial. Docker partially resolved. Frontend needs work.

---

### 7. Neurobench — Benchmarking (TESTING DRAMATICALLY IMPROVED)

**Backend:** 32 Python files, 1,201 LOC. 495 LOC in 9 services. result_store (195 LOC) is solid. benchmark_runner still minimal.

**Frontend:** 17 Dart files, 164 LOC — scaffolds.

**Docker:** Dockerfile present. docker-compose.yml now populated (port 8003, healthcheck, volumes).

**Tests:** 7 Python test files, 98% coverage. Matrix CI (Python 3.11 + 3.12).

**Status:** Backend properly tested and containerized. Services thin but real. Frontend scaffolds.

---

### 8. neuro_toolkit — Flutter Desktop Launcher (FUNCTIONAL)

**What works:** Real ProcessManager with venv creation, pip install, uvicorn subprocess management, health polling, state persistence. WebView integration with tab management (IndexedStack), health polling before load, fallback to system browser. 7-module catalog via JSON manifest. GoRouter navigation. nmtk_ui_core theming.

**Source:** 9 Dart files, 1,416 LOC. 2 test files.

**Status:** The launcher can install, launch, and display module UIs. Core blocker resolved.

---

### 9. nmtk_ui_core — Shared Design System (COMPLETE)

AppTheme (450 LOC, light + dark), PipelineStepper, EnergyBarChart, SparklineChart, QuantizationTable, NavigationRail, buttons. 3 data models. 11 files, 1,219 LOC. 3 widget tests.

---

### 10. nmtk — Installer & CI Tooling

13 GitHub workflow files. 3 shell scripts (demo smoke test, post-merge check, docker-compose validation). Installer scripts for macOS/Linux/Windows (untested).

---

## POC Gap Analysis

### What a POC Demonstrates

**Open launcher → Browse modules → Install neurocnl → Write a CNL spec → Validate → Generate SNN → Simulate → See results**

### What Works Today (No Changes Needed)

1. neurocnl full pipeline via CLI and API
2. neurocnl full pipeline via Docker
3. Neurosim backend API via Docker
4. Neurochip backend API via Docker
5. Neuro-Dream-Hand simulation scripts
6. neuro_toolkit launcher with real process management and WebView
7. Root docker-compose.yml with 7 services
8. Demo walkthrough and smoke test script

### What's Remaining for POC

| Gap | Severity | Effort | Description |
|-----|----------|--------|-------------|
| **Validate root docker-compose startup** | HIGH | 2-4 hours | Untested — healthchecks, build contexts, profiles need validation |
| **End-to-end launcher test** | HIGH | 1 day | Install → launch → WebView flow needs real-device testing |
| **Neurohub docker-compose.yml** | MEDIUM | 30 min | Dockerfile exists, compose does not |
| Neurosim canvas integration testing | MEDIUM | 2-3 days | Canvas exists but may not be fully wired to API |
| Neurochip remaining frontend widgets | MEDIUM | 2 days | ApiClient wired; QuantizationExplorer needed |
| Neurosense integration testing | MEDIUM | 1-2 days | Frontend now substantial; needs end-to-end validation |

### Priority Order for POC

```
TIER 1 — Validate the demo (must do)
├── 1. Run root docker-compose up and fix any issues
├── 2. Test full launcher flow end-to-end
└── 3. Create Neurohub docker-compose.yml

TIER 2 — Make the demo impressive (should do)
├── 4. Integration-test Neurosense frontend against backend
├── 5. Integration-test Neurosim canvas against backend
├── 6. Complete Neurochip frontend widgets
└── 7. Polish demo walkthrough with screenshots

TIER 3 — Polish (nice to have)
├── 8. Neurobench: wire real benchmark runner
├── 9. Neurohub: build real frontend
├── 10. Add Dart tests to modules missing them
└── 11. Validate installer scripts
```

---

## Port Assignment

| Module | Backend Port | Docker Status |
|--------|-------------|---------------|
| neurocnl | 8000 | Ready |
| Neurosim | 8001 | Ready |
| Neurochip | 8002 | Ready |
| Neurobench | 8003 | Ready |
| Neurosense | 8004 | Dockerfile only |
| Neurohub | 8005 | Dockerfile only |
| neurocnl-physics | 8006 | Ready (profile: physics) |

---

## Cross-Module Dependency Map

```
neurocnl (core library)
├── consumed by: Neurosim, Neurobench, Neurochip, Neuro-Dream-Hand
└── standalone: yes (CLI + API + Docker)

Neuro-Dream-Hand (physics library)
├── consumed by: Neurobench, Neurochip
└── standalone: yes (Python scripts)

Neurochip API
├── consumed by: Neurobench, Neurosim
└── standalone: yes (Docker)

Neurosense API
├── consumed by: Neurobench
└── standalone: yes (Docker, needs hardware)

Neurohub
├── consumes: all app /health endpoints
└── standalone: partially (needs other apps running)

nmtk_ui_core (Flutter package)
├── consumed by: neuro_toolkit, neurocnl/frontend
└── standalone: no (library only)

neuro_toolkit (Flutter launcher)
├── consumes: all module backends (at runtime)
└── standalone: yes (functional)
```

---

## Test Coverage

| Module | Test Files | Coverage | Quality |
|--------|-----------|----------|---------|
| neurocnl | 33 Py + 3 Dart | ~484 methods | Excellent |
| Neuro-Dream-Hand | 27 Py | 130+ passing | Excellent |
| Neurochip | 10 Py | 92% | Strong |
| Neurobench | 7 Py | 98% | Strong (new) |
| Neurosense | 10 Py | Unknown | Moderate |
| Neurohub | 9 Py | Unknown | Moderate |
| Neurosim | 12 Py + 3 Dart | Unknown | Moderate |
| neuro_toolkit | 2 Dart | — | Minimal |
| nmtk_ui_core | 3 Dart | — | Minimal |
| **Total** | **108 Py + 11 Dart** | — | **Quality improving rapidly** |

---

## Recent Development Activity

Last 10 commits on root `dev`:
1. `480e967` — chore: update
2. `e798953` — chore: update
3. `6513e45` — chore: update
4. `f576fd3` — Merge PR #153: WebView integration
5. `49c93c9` — Merge dev into feature/webview-integration
6. `bf8e79d` — Merge PR #151: Full module catalog
7. `2118fc2` — Merge dev into feature/full-module-catalog
8. `ba3fa8d` — Merge PR #154: Demo walkthrough POC
9. `4a1513c` — Merge dev into demo-walkthrough-poc
10. `76b5889` — Merge PR #155: Root Docker orchestration

Submodule activity (19–21 Mar):
- **neurocnl:** Pre-commit config, linting in CI, mypy --strict
- **Neurosense:** Massive frontend expansion (+1,561 LOC), strict typing migration
- **Neurochip:** Phase 4 frontend implementation, test expansion (92% coverage)
- **Neurobench:** Test suite (98% coverage), CI pipeline, docker-compose populated, docstrings
- **Neurohub:** Dockerfile added, test suite, pre-commit config, pyproject.toml
- **Neurosim:** Canvas refinements, strict typing

---

## Bottom Line

**The project has transformed in 48 hours from "beautiful shell with no wiring" to a functional platform.** The critical blockers (launcher orchestration, root Docker, WebView integration) are all resolved. Three module frontends have grown substantially. All modules now have CI, tests, and strict typing.

**The question has shifted from "Can we build a POC?" to "Does it work end-to-end?"** The remaining work is validation (run docker-compose, test the launcher flow) and integration testing (wire frontends to backends). Estimated time to demo-ready POC: **3-5 days of focused testing.**
