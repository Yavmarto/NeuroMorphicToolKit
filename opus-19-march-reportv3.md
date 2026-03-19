# NeuroMorphicToolKit — Comprehensive Audit Report v3

**Date:** 2026-03-19  
**Auditor:** Antigravity AI (Gemini)  
**Method:** Automated codebase scan + cross-reference with all prior reports (Opus v1/v2 audit, Opus Status, Sonnet Status, Gemini Status)

---

## Executive Summary

This v3 report performs a full live codebase audit as of 19 March 2026. **The core Python engines (neurocnl, Neuro-Dream-Hand) are production-grade, and 5 out of 6 backends have real service logic.** The neurocnl Flutter frontend is the most advanced (59 Dart files, 5 screens, 11 providers). However, a critical regression has occurred: **`neuro_toolkit` — the desktop launcher that IS the POC — has lost its entire `lib/` directory and `pubspec.yaml`**, reducing it to an empty husk containing only platform runners (ios/android/macos scaffolds and `.dart_tool`). This is the single most important finding.

**Overall POC Readiness: ~50%** (down from 55% in the prior Opus report, due to neuro_toolkit regression)

---

## Codebase Metrics (Live Scan — 19 March 2026)

| Module | Python Files | Python LOC | Dart Files | Dart LOC | Py Test Files | Dart Test Files | CI? |
|--------|-------------|-----------|-----------|---------|--------------|----------------|-----|
| **neurocnl** | 110 | 11,720 | 59 | 8,978 | 30 | 3 | ✅ |
| **Neuro-Dream-Hand** | 93 | 12,320 | — | — | 25 | — | ✅ |
| **Neurosim** | 43 | 1,426 | 14 | 556 | 12 | 3 | ✅ |
| **Neurobench** | 37 | 1,201 | 17 | 164 | 7 | 0 | ✅ |
| **Neurochip** | 39 | 2,032 | 16 | 133 | 10 | 0 | ✅ |
| **Neurosense** | 36 | 2,813 | 20 | 688 | 8 | 0 | ✅ |
| **Neurohub** | 45 | 2,944 | 20 | 238 | 9 | 0 | ⚠️ No ci.yml |
| **neuro_toolkit** | — | — | **0** ❌ | **0** ❌ | — | 0 | ✅ (in root) |
| **nmtk_ui_core** | — | — | 14 | 1,446 | 0 | 0 | ✅ (in root) |
| **nmtk** | — | — | — | — | — | — | N/A |
| **TOTAL** | **403** | **34,456** | **160** | **12,203** | **101** | **6** | |

**Grand Total: 403 Python + 160 Dart = 563 source files, 46,659 lines of code.**

---

## Critical Finding: neuro_toolkit is Empty

The `neuro_toolkit/` directory contains **no `lib/` directory, no `pubspec.yaml`, and no Dart source code**. The only files present are platform runner scaffolds (`ios/`, `android/`, `macos/`) and `.dart_tool/` cache. This appears to be a recent regression — the Opus Status report from 17 March described 6 Dart files and ~2,000 LOC with DashboardScreen, CatalogScreen, ToolViewScreen, etc.

**Impact:** The launcher application — which IS the POC — cannot be built, run, or tested in its current state.

**Recommended Action:** Immediately restore from git history or recreate the Flutter app shell.

---

## Module Deep-Dive

### 1. neurocnl — CNL Compiler & SNN Engine ✅ READY

The most mature module. End-to-end functional.

| Aspect | Detail |
|--------|--------|
| Python library | v0.3.0, 13 CNL concepts, 18 biological invariants, 5 export formats |
| Backend | 9 core routers + 5 prosthetic routers, async job system |
| Frontend | 5 screens (Studio, Deploy, Hardware, Analysis, Server), 11 Riverpod providers, GoRouter |
| Tests | 30 Python test files, 3 Dart test files |
| Docker | docker-compose.yml present, multi-stage build |
| Submodule status | Local modifications (`+` prefix), 68 commits ahead of v0.2.0 tag |

**POC Status:** Can demo today. No blockers.

---

### 2. Neuro-Dream-Hand — Prosthetic SNN Simulator ✅ READY

Production-quality research library. Standalone Python — no web frontend.

| Aspect | Detail |
|--------|--------|
| LOC | 12,320 across 93 Python files |
| Capabilities | MuJoCo bridge, SNN controller, PES sleep learning, quantization, fault injection, Teensy serial, EMG encoding |
| Tests | 25 test files |
| CI | Full pipeline with integration tests |

**POC Status:** Ready for simulation demos. Hardware validation requires physical devices.

---

### 3. Neurosim — Visual SNN Designer ⚠️ BACKEND COMPLETE, FRONTEND MINIMAL

| Aspect | Detail |
|--------|--------|
| Backend | 43 Python files, 1,426 LOC. All 12 API endpoints implemented (components, templates, validation, CNL gen, preview, sweep, export, projects). 535 LOC in routers alone. |
| Services | `graph_to_cnl.py`, `cnl_to_graph.py`, `preview_runner.py`, `sweep_runner.py` — all implemented |
| Frontend | 14 Dart files, 556 LOC. Has `network_canvas.dart`, `cnl_editor.dart`, `export_dialog.dart` + models + providers — **more than zero**, but not a complete canvas implementation |
| Tests | 12 Python + 3 Dart test files |
| Docker | Dockerfile + docker-compose.yml present |

**POC Status:** Backend ready. Frontend has basic structure but the complex CustomPainter canvas is incomplete. Could demo via Swagger/API docs.

---

### 4. Neurochip — Hardware Deployment Toolkit ⚠️ BACKEND STRONG

| Aspect | Detail |
|--------|--------|
| Backend | 39 Python files, 2,032 LOC. **1,092 LOC in services alone** — constraint analyzer, quantizer, power estimator, teensy generator, flash service, loihi generator, partitioner, fault runner, deployment store. This is real logic, not stubs. |
| Frontend | 16 Dart files, 133 LOC. TargetSelector, QuantizationExplorer, ConstraintReportCard, FaultInjectionPanel all exist as files but are likely scaffolds. |
| Tests | 10 Python test files |
| Docker | Present |
| Hardware profiles | 5 targets (Teensy 4.1, Loihi 2, Akida, SpiNNaker, BrainScaleS) |

**POC Status:** Backend is strong and testable. Frontend needs widget implementation to become demo-able.

---

### 5. Neurosense — Biosignal Acquisition ⚠️ BACKEND STRONG, FRONTEND HALF-BUILT

| Aspect | Detail |
|--------|--------|
| Backend | 36 Python files, 2,813 LOC. **1,114 LOC in services** — device manager (243 LOC), filter pipeline (140 LOC), recording service (216 LOC), spike encoder (173 LOC), quality analyzer (152 LOC), replay service (122 LOC). Surprisingly complete. |
| Frontend | 20 Dart files, 688 LOC. DeviceSelector with state management, live signal viewer, recording controls, spike encoding panel, pipeline connector. Most comprehensive frontend after neurocnl. |
| Tests | 8 Python test files |
| Docker | Present |

**POC Status:** Most functional after neurocnl for end-to-end demo. Needs physical hardware for full validation.

---

### 6. Neurohub — Suite Dashboard & Orchestrator ⚠️ SERVICES IMPLEMENTED, NO CI

| Aspect | Detail |
|--------|--------|
| Backend | 45 Python files, 2,944 LOC. **937 LOC in services** — workflow engine (245 LOC), suite client (170 LOC), asset library (126 LOC), project service (123 LOC), milestone tracker (95 LOC), activity collector (86 LOC), config service (64 LOC), health checker (27 LOC). |
| Frontend | 20 Dart files, 238 LOC. 8 screens, 11 widgets — but likely scaffolds based on low LOC. |
| Tests | 9 Python test files |
| Docker | **MISSING** — no Dockerfile or docker-compose.yml |
| CI | **MISSING** — only module without a `ci.yml` (has auto-merge and bug-fixer workflows only) |

**POC Status:** Backend has substantial service implementations. Missing Docker and CI are quality gaps.

---

### 7. Neurobench — Benchmarking Workbench ⚠️ IMPROVED FROM STUBS

| Aspect | Detail |
|--------|--------|
| Backend | 37 Python files, 1,201 LOC. **495 LOC in services** — result store (195 LOC), diff engine (73 LOC), benchmark loader (58 LOC), target comparator (49 LOC), fault sweeper (28 LOC), encoding comparator (26 LOC), perturbation sweeper (21 LOC). |
| Frontend | 17 Dart files, 164 LOC — thin scaffolds. |
| Tests | 7 Python test files (up from 0 in v1) |
| Docker | Dockerfile present, docker-compose.yml may be incomplete |
| CLI | `cli/__main__.py` exists — needs implementation |

**Assessment update:** Prior reports called Neurobench "mostly stubs." The services now contain real (if thin) implementations. The benchmark_runner at 22 LOC is still likely a stub, but diff_engine, result_store, and benchmark_loader are functional.

---

### 8. neuro_toolkit — Desktop Launcher ❌ CRITICAL: EMPTY

| Aspect | Detail |
|--------|--------|
| Source files | **0** — `lib/` directory does not exist |
| pubspec.yaml | **Missing** |
| Present files | Only platform scaffolds (ios/, android/, macos/) and .dart_tool cache |

**This is THE critical blocker.** The entire launcher application has been deleted or was never committed to the current branch. All prior reports described functional Dart files here.

---

### 9. nmtk_ui_core — Shared Design System ✅ COMPLETE

| Aspect | Detail |
|--------|--------|
| Files | 14 Dart files, 1,446 LOC |
| Components | AppTheme (light+dark), NmtkDesignTokens, ResponsiveScaffold, NavigationRail, charts, buttons |
| Tests | 0 widget tests |

**Status:** Functionally complete. Used by neurocnl/frontend and (previously) neuro_toolkit.

---

### 10. nmtk — Installer & CI Tooling

Contains installer scripts (DMG, AppImage, Inno Setup), environment setup scripts, CI configs. No source code. 9 config/script files.

---

## Infrastructure Status

| Aspect | Status |
|--------|--------|
| Root CI (`ci.yml`) | ✅ Monorepo path-filter CI covering all modules |
| Per-module CI | ✅ All except Neurohub |
| Docker | 5/6 backends have Dockerfiles (missing: Neurohub) |
| Root Docker | ❌ No root docker-compose.yml |
| Submodule health | 4 submodules have local modifications (Neurohub, Neurosense, Neurosim, neurocnl) |
| Pre-commit hooks | ❌ None in any module |
| Shared UI package | ✅ nmtk_ui_core is complete |

---

## Service Implementation Depth (LOC in `services/`)

This is the strongest indicator of real vs stub backend logic:

| Module | Services LOC | Assessment |
|--------|-------------|------------|
| Neurosense | 1,114 | **Strong** — 7 services with substantial logic |
| Neurochip | 1,092 | **Strong** — 9 services with real math/generation |
| Neurohub | 937 | **Moderate** — 8 services, workflow engine is real |
| Neurobench | 495 | **Thin** — result_store solid, runner still minimal |
| Neurosim | N/A (in routers) | **Strong** — 535 LOC in routers with real logic |

---

## What Changed Between Opus Status (17 Mar) and Today (19 Mar)

| Area | 17 Mar Assessment | 19 Mar Reality |
|------|-------------------|----------------|
| neuro_toolkit | "90% shell, 6 Dart files, ~2000 LOC" | **0 files, 0 LOC — lib/ deleted** ❌ |
| Neurobench tests | "0 test files" | **7 test files** ✅ |
| Neurochip tests | "3 test files" | **10 test files** ✅ |
| Neurosim tests | "~6 test files" | **12 py + 3 dart test files** ✅ |
| Neurosense tests | "1 file" | **8 test files** ✅ |
| Neurohub tests | "2 files" | **9 test files** ✅ |
| Neurosim frontend | "0% / none" | **14 Dart files, 556 LOC — basic canvas and models exist** |
| Root CI | "None" | **ci.yml with monorepo path detection** ✅ |
| neurocnl frontend | "85% / 8,962 LOC" | **8,978 LOC, 59 files** ✅ Confirmed |

---

## Corrections to Prior Reports

| Prior Claim | Correction |
|-------------|------------|
| Opus: "neuro_toolkit has 6 Dart files, ~2000 LOC" | **Wrong today** — lib/ is completely missing |
| Sonnet: "Neurosim frontend is 0%" | **Partially wrong** — 14 files with 556 LOC exist including canvas stub and models |
| Gemini: "Neurochip Phase 1 only" | **Wrong** — constraint analyzer, quantizer, generators, flash service all implemented (1,092 service LOC) |
| All reports: "Neurobench has zero tests" | **Wrong today** — 7 test files exist |
| Opus: "Neurohub has 2 test files" | **Wrong today** — 9 test files exist |
| Opus: "No root CI" | **Wrong today** — root ci.yml with full monorepo path filtering |
