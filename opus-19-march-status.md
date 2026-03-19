# NeuroMorphicToolKit — Status Report

**Generated:** 19 March 2026
**Branch:** dev
**Assessor:** Claude Opus 4.6
**Method:** Full codebase exploration + cross-reference with Sonnet/Gemini/Opus status reports

---

## Executive Summary

The NeuroMorphicToolKit is a multi-module neuromorphic computing platform: a Flutter desktop launcher (`neuro_toolkit`) that orchestrates 7 Python/FastAPI backend modules, each with its own Flutter frontend. Two core Python libraries (`neurocnl` and `Neuro-Dream-Hand`) are production-quality. Four backends are functionally complete. The launcher shell works but **cannot actually start or manage any backend process** — this remains the single biggest POC blocker.

**Overall POC Readiness: ~55%**

- Core Python engine: DONE
- Backend APIs: 4 of 6 fully implemented
- Frontend UIs: 1 complete (neurocnl), 5 partial/missing
- Launcher orchestration: NOT IMPLEMENTED (mock only)
- Root-level Docker orchestration: DOES NOT EXIST

---

## What Changed Since Last Reports

Comparing the three prior assessments (Gemini undated, Opus 17-Mar, Sonnet 19-Mar) against today's live codebase:

| Area | Previous Status | Current Reality |
|------|----------------|-----------------|
| neurocnl frontend | Sonnet: "near complete" / Opus: "30% scaffold" | **Near-complete** — 58 Dart files, 8,962 LOC, 5 screens (Studio, Deploy, Hardware, Analysis, Server). Sonnet was correct. |
| Neurosim frontend | All reports: "0% / not started" | **Still 0%** — 14 Dart files exist but only boilerplate (556 LOC total). No canvas implementation. |
| Neurochip backend | Gemini: "Phase 1 only" / Sonnet: "Phases 1–3 complete" | **Sonnet correct** — constraint analyzer, quantizer, power estimator, firmware generator, flash service all implemented. 32 Python files, 1,593 LOC. |
| Neurosense backend | Gemini: "scaffolding only" / Opus: "80%" | **Opus correct** — device manager (245 LOC), filter pipeline, spike encoder, recording service, quality analyzer all implemented. 27 files, 2,217 LOC. |
| Neurobench | All reports: "stubs/incomplete" | **Still stubs** — BenchmarkRunner generates random IDs, zero tests, blank docker-compose.yml. |
| neuro_toolkit orchestration | All reports: "mock only" | **Still mock only** — no subprocess management, no Docker integration. |
| nmtk_ui_core | Sonnet: "complete" | **Complete** — AppTheme, NmtkThemeExtension, ResponsiveScaffold all working. No widget tests. Recent refactor landed (PR #133). |
| neurocnl submodule | — | **Has local modifications** (`+` prefix in submodule status). HEAD at `0ddbabe`, 62 commits ahead of v0.2.0 tag. |
| Root Docker orchestration | Not mentioned | **Does not exist** — no root docker-compose.yml. Each module has its own. |

---

## Module Status Matrix

| Module | Backend | Frontend | Docker | Tests | LOC (Py) | LOC (Dart) | POC Ready? |
|--------|---------|----------|--------|-------|----------|------------|------------|
| **neurocnl** | 95% | 85% | Yes (2 Dockerfiles) | 305 passing (34 files) | 11,201 | 8,962 | YES |
| **Neuro-Dream-Hand** | 95% (library) | N/A | No | 130 passing (28 files) | 12,320 | — | YES (sim only) |
| **Neurosim** | 90% | 0% | Yes | ~6 files | 1,166 | 556 | Backend only |
| **Neurochip** | 90% | 40% | Yes | 3 files | 1,593 | 109 | Backend only |
| **Neurosense** | 90% | 50% | Yes | 1 file | 2,217 | 688 | Backend only |
| **Neurohub** | 75% | 10% | No | 2 files (27 tests) | 1,978 | 238 | No |
| **Neurobench** | 35% (stubs) | 40% (mock) | Broken | 0 | 930 | 164 | No |
| **neuro_toolkit** | N/A | 80% shell | N/A | 0 (broken) | — | ~2,000 | BLOCKED |
| **nmtk_ui_core** | N/A | 100% | N/A | 0 | — | ~1,500 | Yes |
| **nmtk** | N/A | N/A | N/A | N/A | — | — | Untested |

**Totals:** ~31,400 Python LOC | ~14,200 Dart LOC | 490 modules | 435+ passing tests | 73 test files

---

## Detailed Module Status

### 1. neurocnl — CNL Compiler & SNN Engine (READY)

The crown jewel. Fully functional end-to-end pipeline.

**Python library (v0.3.0):** 13 CNL concepts, 18 biological invariants, regex-based parser, Nengo code generator, 5 export formats (NeuroML, C header, NengoLoihi, Lava, SpiNNaker), spike encoding (rate/temporal/delta), visualization, CLI.

**FastAPI backend:** 12 routers — `/api/parse`, `/validate`, `/generate`, `/simulate`, `/export`, `/jobs`, plus 5 prosthetic endpoints. Async job system for long simulations.

**Flutter frontend:** 5 screens — Studio (CNL editor), Deploy, Hardware, Analysis, Server Setup. Uses Riverpod + GoRouter. 58 Dart files.

**Docker:** Multi-stage build. Backend on `:8000`, frontend on `:8080`. `docker-compose up` works.

**Tests:** 305 passing across 34 test files (~25s runtime).

**Status:** Can demo today. No blockers.

---

### 2. Neuro-Dream-Hand — Prosthetic SNN Simulator (READY)

Production-quality research library. No web service — standalone Python.

**Capabilities:** MuJoCo physics bridge (817 LOC), SNN reflex controller (213 LOC), PES sleep learning (30-day consolidation), online continual learning, INT-N quantization (4-32 bit), 3 fault injection modes, pJ/SOP power estimates, Teensy serial bridge, EMG spike encoder (BrainFlow/Ganglion), 13 tutorial scripts.

**Tests:** 130 passing across 28 files.

**Limitation:** All hardware I/O is mock-tested. Loihi 2 requires Intel NxSDK.

---

### 3. Neurosim — Visual SNN Designer (BACKEND COMPLETE, NO FRONTEND)

**Backend:** 13 API endpoints all functional — components catalog, templates, validation, CNL generation/parsing, simulation preview, parameter sweeps, multi-format export, project CRUD. 25 Python files.

**Frontend:** Boilerplate only. The 14 Dart files contain no canvas implementation. NS-D1 through NS-D5 stories are all pending. This is the **hardest single frontend sprint** in the project.

**Docker:** Ready. `docker-compose up` starts the backend.

---

### 4. Neurochip — Hardware Deployment Toolkit (BACKEND STRONG, FRONTEND PARTIAL)

**Backend:** Constraint analyzer, quantizer (mathematical models), power estimator, Teensy firmware generator (Jinja2 templates), PlatformIO flash service, fault runner. 5 hardware profiles: Teensy 4.1, Loihi 2, Akida, SpiNNaker, BrainScaleS.

**Frontend:** TargetSelector widget and API client work. QuantizationExplorer, ConstraintReportCard, FirmwareGeneratorPanel, FlashProgressIndicator are stubs.

**Docker:** Ready.

---

### 5. Neurosense — Biosignal Acquisition (BACKEND STRONG, FRONTEND PARTIAL)

**Backend:** BrainFlow device manager (245 LOC), Butterworth filter pipeline, spike encoder (wraps neurocnl), HDF5 recording service, SNR/impedance quality analyzer, 4 acquisition presets, WebSocket streaming endpoints. Surprisingly complete.

**Frontend:** DeviceSelector with full state management works. Signal viewer, session browser, setup wizard are partially implemented.

**Limitation:** Requires physical OpenBCI hardware to validate beyond mock tests.

---

### 6. Neurohub — Suite Dashboard (DATABASE WORKS, REST IS STUBS)

**Backend:** SQLAlchemy ORM with 8 models. Full Projects CRUD tested (27 tests passing). Workflow engine, activity collector, health checker, suite_client — all stubs returning mock data.

**Frontend:** DashboardScreen is literally 3 lines of code. Other screen files exist but are mostly scaffolding.

**No Docker support.**

---

### 7. Neurobench — Benchmarking (MOSTLY STUBS)

**Backend:** Router/schema structure exists. BenchmarkRunner generates random job IDs instead of running real benchmarks. SQLite result store is implemented. 5 built-in benchmark definitions (JSON).

**Frontend:** Catalog and results UI exist but display hardcoded mock data.

**Docker:** `docker-compose.yml` exists but is **blank/empty**.

**Tests:** Zero.

**CLI:** `cli/__main__.py` is an empty stub.

---

### 8. neuro_toolkit — Flutter Desktop Launcher (SHELL ONLY)

**What works:** Main app with bottom navigation (Dashboard ↔ Catalog), module list with Install/Launch/Uninstall buttons, ToolViewScreen with mock terminal output, nmtk_ui_core theming integration, GoRouter navigation (recently overhauled in PR #132).

**What doesn't work:** Installation simulates download with a timer (no real download). Launch opens a mock terminal view (no actual process start). No WebView integration. No Docker/subprocess management. Only 3 hardcoded modules in catalog. Test file is broken.

**This is THE critical blocker.** Every other module can run independently via `docker-compose` or `uvicorn`, but the launcher — which IS the POC — cannot orchestrate any of them.

---

### 9. nmtk_ui_core — Shared Design System (COMPLETE)

AppTheme (light + dark), NmtkDesignTokens, NmtkThemeExtension (glassmorphism, gradients, syntax highlighting), ResponsiveScaffold. Used by neuro_toolkit and neurocnl/frontend. Recently refactored (PR #133).

No widget tests, but functionally complete.

---

### 10. nmtk — Installer & CI Tooling (SCRIPTS EXIST, UNTESTED)

Installer scripts for macOS (DMG), Linux (AppImage), Windows (Inno Setup). Environment setup scripts. CI configuration (Ruff, mypy, Codecov, Trivy, Dependabot, pre-commit, git-cliff, semantic-release). Teensy servo firmware sketch.

Not validated on actual machines.

---

## POC Gap Analysis

### What a POC Demonstrates

**Open launcher → Browse modules → Install neurocnl → Write a CNL spec → Validate → Generate SNN → Simulate → See results**

### What Works Today (No Changes Needed)

1. neurocnl full pipeline via CLI: `neurocnl examples/slip_reflex.cnl`
2. neurocnl full pipeline via API: `docker-compose up` in neurocnl/
3. Neurosim backend API: `docker-compose up` in Neurosim/
4. Neurochip backend API: `docker-compose up` in Neurochip/
5. Neuro-Dream-Hand simulation: `python scripts/step3_reflex.py`
6. neuro_toolkit shell UI: `flutter run -d macos` (displays mock data)

### What's Broken / Missing for POC

| Gap | Severity | Effort | Description |
|-----|----------|--------|-------------|
| **Launcher can't start backends** | CRITICAL | 3-5 days | neuro_toolkit's ModuleProvider uses a timer to fake installation. Need real subprocess/Docker management. |
| **No WebView in launcher** | CRITICAL | 2-3 days | After starting a backend, the launcher needs to display its UI (either via webview_flutter or embedded Flutter). |
| **No root orchestration** | HIGH | 1 day | No root docker-compose.yml to bring up all services. Each module is isolated. |
| **Neurosim has no frontend** | HIGH | 5-7 days | The "visual SNN designer" has zero canvas implementation. Backend is solid. |
| **Only 3 modules in launcher catalog** | MEDIUM | 2 hours | neuro_toolkit only lists Neuro-Dream-Hand, neurocnl, nmtk. Missing Neurosim, Neurochip, Neurobench, Neurosense, Neurohub. |
| **Neurobench is non-functional** | MEDIUM | 3-5 days | Stubs everywhere, zero tests, blank Docker config. |
| **Neurohub stubs** | LOW | 3-5 days | Activity collector, health checker, suite_client all return mock data. |
| **Installer scripts untested** | LOW | 1-2 days | May not work on actual target platforms. |

### Priority Order for POC

```
TIER 1 — Unlock the demo (must do)
├── 1. Wire neuro_toolkit to actually start/stop Docker containers
├── 2. Add WebView to display module UIs in the launcher
├── 3. Add all 7 modules to the launcher catalog
└── 4. Create a root docker-compose.yml for one-command startup

TIER 2 — Make the demo impressive (should do)
├── 5. Neurosim: minimal canvas UI (even just a WebView to /docs)
├── 6. Neurochip: finish QuantizationExplorer widget
└── 7. Write a demo script / walkthrough

TIER 3 — Polish (nice to have)
├── 8. Neurobench: wire CLI + real benchmark runner
├── 9. Neurohub: real health checker + activity feed
├── 10. Fix neuro_toolkit test file
└── 11. Validate installer scripts
```

---

## Port Assignment

| Module | Backend Port | Frontend Dev Port | Docker Status |
|--------|-------------|-------------------|---------------|
| neurocnl | 8000 | 8080 / 3000 | Ready |
| Neurosim | 8001 | 3001 | Ready |
| Neurochip | 8002 | 3002 | Ready |
| Neurobench | 8003 | 3003 | Broken |
| Neurosense | 8004 | 3004 | Ready |
| Neurohub | 8005 | 3005 | Missing |

---

## Cross-Module Dependency Map

```
neurocnl (core library)
├── consumed by: Neurosim, Neurobench, Neurochip, Neuro-Dream-Hand
└── standalone: yes (CLI + API + Docker)

Neuro-Dream-Hand (physics library)
├── consumed by: Neurobench (fault sweeper), Neurochip (crossbar export)
└── standalone: yes (Python scripts)

Neurochip API
├── consumed by: Neurobench (cross-target comparison), Neurosim (NS-E2)
└── standalone: yes (Docker)

Neurosense API
├── consumed by: Neurobench (encoding comparison)
└── standalone: yes (Docker, needs hardware)

Neurohub
├── consumes: all app /health endpoints
└── standalone: partially (needs other apps running)

nmtk_ui_core (Flutter package)
├── consumed by: neuro_toolkit, neurocnl/frontend
└── standalone: no (library only)

neuro_toolkit (Flutter launcher)
├── consumes: all module backends (at runtime)
└── standalone: yes (but mock-only today)
```

---

## Test Coverage

| Module | Test Files | Passing Tests | Coverage Quality |
|--------|-----------|---------------|-----------------|
| neurocnl | 34 | 305 | Excellent |
| Neuro-Dream-Hand | 28 | 130 | Excellent |
| Neurohub | 2 | 27 | Projects CRUD only |
| Neurosim | 5 | ~unknown | API-level only |
| Neurochip | 3 | ~unknown | Minimal |
| Neurosense | 1 | ~unknown | Integration only |
| Neurobench | 0 | 0 | None |
| neuro_toolkit | 0 | 0 | Broken test file |
| nmtk_ui_core | 0 | 0 | None |
| **Total** | **73** | **462+** | **Two modules carry 94% of all tests** |

---

## Recent Development Activity

Last 5 commits on `dev`:
1. `d9c8d9c` — updated neuro sim (submodule pointer)
2. `8b0edae` — PR #133: nmtk_ui_core refactor (NMTK-21)
3. `98cbc0a` — merge dev into UI core branch
4. `572c98b` — PR #132: GoRouter overhaul (NMTK-19)
5. `741b0cb` — PR #131: Navigation rail (NMTK-20)

Recent focus has been on **launcher UI infrastructure** — routing, navigation, and theming. Backend modules have been stable.

---

## Bottom Line

The **engine works**, the **backends work**, but the **glue doesn't exist yet**. The launcher is a beautiful shell with no wiring. A 2-week focused sprint on (1) subprocess orchestration in neuro_toolkit and (2) a minimal Neurosim canvas would produce a compelling POC that demonstrates the full CNL → SNN → simulation → hardware export pipeline through a unified desktop app.
