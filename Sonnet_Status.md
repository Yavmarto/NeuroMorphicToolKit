# NeuroMorphicToolKit — Complete Status Report
**Generated:** 19 March 2026 | **Model:** Claude Sonnet 4.6

---

## Executive Summary

The NMTK suite is a **Launcher + Micro-Service Container** architecture: a Flutter desktop app (`neuro_toolkit`) as the unified entry point that installs and launches Python/FastAPI backend modules, each serving its own Flutter frontend via a local WebView.

**Overall POC readiness: ~55%**

The core engine (`neurocnl`) and physics simulation (`Neuro-Dream-Hand`) are production-quality. Three backends (Neurosim, Neurochip, Neurobench) are fully implemented. The blocking gap for a working POC is that **no module frontend is complete enough to demo end-to-end**, and the `neuro_toolkit` launcher's orchestration logic (spinning up Docker/venvs automatically) is a stub.

---

## Module-by-Module Status

---

### 1. neurocnl — CNL Compiler & SNN Engine
**Role:** The core engine. Parses plain-English behavioral specs into executable Nengo spiking neural networks and exports them to 5 hardware formats.

| Layer | Status | Detail |
|---|---|---|
| Python library | ✅ Complete | v0.3.0 — 13 CNL concepts, 18 biological invariants, 5 exporters |
| FastAPI backend | ✅ Complete | 12 routers (`/api/parse`, `/validate`, `/generate`, `/simulate`, `/export`, `/jobs`, 5 prosthetic endpoints) |
| Flutter frontend | ✅ Near complete | 5 screens: Studio, Deploy, Hardware, Analysis, Server Setup (Riverpod, go_router) |
| Docker | ✅ Ready | `docker-compose.yml` — backend `:8000`, frontend `:3000` |
| Tests | ✅ 305 passing | 26 test files, ~25s runtime |
| Phase 8 (BrainFlow live) | ❌ Not started | Stub only |

**POC Blocker:** None — this module can run today.

**Dependencies:** None (this is the foundation).

---

### 2. Neuro-Dream-Hand — Prosthetic SNN Simulator
**Role:** Physics-accurate neuromorphic prosthetic hand simulation. Nengo SNN controller + MuJoCo physics + continual learning. Also provides the fault injection, quantization analysis, and power profiling library used by Neurobench and Neurochip.

| Layer | Status | Detail |
|---|---|---|
| Simulation phases 1–3 | ✅ Production quality | MuJoCo bridge (817 lines), SNN controller (213 lines), PES sleep/online learning, 30-day consolidation validated |
| Hardware simulation | ✅ Software-only | INT-N quantization, 3 fault injection modes, pJ/SOP power estimates — all mock-tested |
| Hardware I/O | ⚠️ Code complete, untested | Serial bridge (Teensy), EMG streamer (BrainFlow/Ganglion) — mock-tested only, no real devices |
| Loihi 2 / Akida deployment | ⚠️ Code stub | Requires Intel SDK access + physical chip |
| Docker | ❌ No Dockerfile | Pure Python package, not a service |
| Tests | ✅ 130 passing, 1 skipped | 25 test files, ~25s runtime |

**POC Blocker:** None for simulation. Real hardware requires Teensy + OpenBCI Ganglion.

**Dependencies:** `nengo>=4.0.0`, `mujoco>=3.1.0` (optional for physics).

---

### 3. Neurosim — Visual SNN Design Workbench
**Role:** Drag-and-drop canvas for visual SNN design. Generates CNL specs from graphical networks, runs simulations and parameter sweeps, exports to multiple formats.

| Layer | Status | Detail |
|---|---|---|
| FastAPI backend | ✅ Complete | All 13 endpoints: components, templates, validate, generate-cnl, parse-cnl, preview, sweep, simulate, export, projects (CRUD) |
| Flutter frontend | ❌ Not started | All NS-D1–D5 canvas design stories pending; simulation screens exist on backend only |
| Docker | ✅ Ready | Dockerfile + docker-compose — backend `:8000` |
| Tests | ⚠️ 6 test files | Pass count unconfirmed; style checks pass |

**POC Blocker:** Entire frontend. The API surface is complete — a frontend sprint could close this.

**Dependencies:** `neurocnl` library (for validate/simulate calls).

---

### 4. Neurochip — Hardware Deployment Toolkit
**Role:** Compiles SNN specs to chip-specific firmware. Checks hardware constraints (Teensy 4.1, Loihi 2, Akida, SpiNNaker, BrainScaleS), runs quantization sweeps, generates C/Jinja firmware, flashes via PlatformIO.

| Layer | Status | Detail |
|---|---|---|
| FastAPI backend | ✅ Phases 1–3 complete | All Pydantic schemas, all API routes, constraint analyzer, quantizer, power estimator, fault runner, firmware generator, flash service, deployment store |
| Hardware profiles | ✅ JSON files populated | `teensy41.json`, `loihi2.json`, etc. in `targets/` |
| Jinja2 firmware templates | ✅ Listed as done | `main.ino.j2`, `lif_engine.h.j2`, `deploy.py.j2` |
| Flutter frontend | ⚠️ Phase 4 partial | API client, HardwareProfile model, Riverpod targets provider, TargetSelector widget done. QuantizationExplorer, ConstraintReportCard, FirmwareGeneratorPanel, FlashProgressIndicator not built |
| Docker | ✅ Ready | Backend `:8000` |
| Tests | ⚠️ 3 test files | `test_routers.py`, `test_constraint_analyzer.py`, `test_main.py` — pass count unconfirmed |

**POC Blocker:** Incomplete frontend. Backend is solid and callable via API.

**Dependencies:** `neurocnl` (export formats), `neurodreamhand` (crossbar export, fault injection).

---

### 5. Neurobench — Benchmarking Workbench
**Role:** Runs standardized benchmark suites against SNN designs. Compares against baselines, sweeps fault/perturbation injection, integrates with Neurochip for cross-target comparison, generates PDF/HTML reports.

| Layer | Status | Detail |
|---|---|---|
| Pydantic schemas | ✅ Complete | `BenchmarkDefinition`, `BenchmarkResult`, `DiffResult`, `RobustnessCurve`, etc. |
| FastAPI backend | ✅ Services complete | 14 endpoints wired to real services: `benchmark_runner.py`, `diff_engine.py`, `fault_sweeper.py`, `perturbation_sweeper.py`, `target_comparator.py`, `report_generator.py` |
| Builtin benchmark JSONs | ✅ Populated | Grip stability, spike classification, wake-word detection, pattern recognition |
| CLI (`neurobench run ...`) | ❌ Empty stub | `cli/__main__.py` exists, no implementation |
| Flutter frontend | ⚠️ Shell only | ListView catalog, results card, metric diff table — hardcoded mock data |
| Docker | ❌ Empty `docker-compose.yml` | File exists but is blank |
| Tests | ❌ Zero tests | Milestone 8 lists tests as not started |

**POC Blocker:** CLI stub, no Docker config, zero tests. Business logic is written but untested and has no entry point.

**Dependencies:** `neurocnl`, `neurodreamhand` (fault injection), Neurochip API, Neurosense API.

---

### 6. Neurohub — Suite Dashboard & Orchestration
**Role:** The central management dashboard. Monitors all apps' health, aggregates activity feeds, manages cross-app projects/milestones/assets, and provides team collaboration.

| Layer | Status | Detail |
|---|---|---|
| FastAPI structure | ✅ Seeded | 10 routers scaffolded; Projects CRUD fully implemented |
| Database | ✅ SQLite/SQLAlchemy | Schema migrated, working |
| Service layer | ⚠️ Mostly stubs | `activity_collector.py`, `workflow_engine.py`, `health_checker.py`, `suite_client.py` all stub/mock |
| Flutter frontend | ⚠️ Minimal | DashboardScreen shell only; no API client, no Riverpod providers, no real screens |
| Docker | ❌ No Dockerfile | Not containerized |
| Tests | ⚠️ 27 tests | Projects endpoint only; no cross-suite tests |

**POC Blocker:** Service layer stubs, no frontend beyond a placeholder screen, no Docker.

**Dependencies:** All other apps (polls their `/health` + `/activity` endpoints).

---

### 7. Neurosense — Biosignal Acquisition Toolkit
**Role:** Connects to OpenBCI hardware (Ganglion/Cyton), streams multi-channel EEG/EMG, filters signals (Butterworth), and encodes them into spike trains for downstream SNN consumption.

| Layer | Status | Detail |
|---|---|---|
| FastAPI backend | ⚠️ Device management only | NSe-DM1 API (device discovery/connection). Signal acquisition, recording, encoding endpoints not implemented |
| Flutter frontend | ⚠️ DeviceSelector only | `DeviceProvider` + `DeviceSelector` widget. All signal viewer and spike encoding screens pending |
| Docker | ⚠️ Empty compose | `docker-compose.yml` is a stub |
| Tests | ⚠️ 1 test file | `test_main.py` — minimal coverage |

**POC Blocker:** Everything beyond device listing. Realistically requires physical OpenBCI hardware to validate.

**Dependencies:** `brainflow`, `scipy`, `h5py`. Feeds into Neurobench for real-signal benchmarks.

---

### 8. neuro_toolkit — Flutter Desktop Launcher
**Role:** The unified desktop application. An "App Store + WebView launcher" that downloads modules, spins up their Docker backends, and presents their UIs in-app via WebView tabs.

| Layer | Status | Detail |
|---|---|---|
| App shell | ✅ Working | `main.dart`, `MainScreen` with bottom nav (Dashboard ↔ Catalog), `AppTheme` from `nmtk_ui_core` |
| DashboardScreen | ✅ Shell | Lists installed modules, Launch button (opens `ToolViewScreen`/WebView), Uninstall wired to `ModuleProvider` |
| CatalogScreen | ✅ Shell | Lists available modules for install |
| `ModuleProvider` | ⚠️ State only | Install/uninstall state tracked; actual Docker/venv spin-up logic is a stub |
| Module orchestration | ❌ Not implemented | Downloading packages, starting Docker containers, managing PIDs — none of this is wired |
| Tests | ❌ None | No widget tests written |

**POC Blocker:** Module orchestration (Docker spin-up from Flutter). This is the hardest piece — needs subprocess management or a local daemon.

**Dependencies:** `nmtk_ui_core` (path dep), all module backends (runtime).

---

### 9. nmtk_ui_core — Shared Flutter Design System
**Role:** Brand tokens, `AppTheme` (light + dark), `NmtkThemeExtension` (glassmorphism, gradients, syntax highlight colors), `ResponsiveScaffold` — consumed by `neuro_toolkit` and `neurocnl/frontend`.

| Layer | Status | Detail |
|---|---|---|
| Theme + tokens | ✅ Complete | `NmtkDesignTokens`, `NmtkThemeExtension`, `AppTheme.lightTheme`/`darkTheme` |
| Generic components | ❌ Not started | NMTK-21: buttons, charts, form fields — issue filed, not implemented |
| Tests | ❌ None | |

**POC Impact:** Low priority for POC. Theme works today.

---

### 10. nmtk — CLI, Installer & CI Tooling
**Role:** Bash installer scripts for macOS/Linux/Windows, Teensy servo firmware sketch, CI configuration (Ruff, mypy, Codecov, Trivy, Dependabot, pre-commit, git-cliff, semantic-release, Sphinx). Not a Python package — a tooling directory.

| Layer | Status | Detail |
|---|---|---|
| CI/tooling issues (NMTK-22–30) | ✅ Archived/done | Ruff, mypy, unified CI, Dependabot, Trivy+CodeQL, pre-commit, Codecov, git-cliff, semantic-release all landed |
| Installer scripts | ✅ Scaffolded | `installer/linux/`, `installer/macos/`, `installer/windows/` |
| Teensy firmware | ✅ Sketch present | `servo_control/` — C++ sketch for servo actuation |
| Global ROADMAP | ✅ Maintained | Tracks v0.3.0 milestone (completed) + future phases |

**POC Impact:** Installers are the delivery mechanism for setting up module environments on end-user machines.

---

## POC Definition & Priority Order

A minimal POC demonstrates: **write a CNL spec → simulate an SNN → inspect the result**. This requires only the `neurocnl` backend and any frontend (even the CLI/API).

### Tier 1 — Can Run Today (No Code Changes)
| Module | What works | How |
|---|---|---|
| **neurocnl** | Full pipeline: parse → validate → generate → simulate → export | `docker-compose up` in `neurocnl/` |
| **Neuro-Dream-Hand** | Full SNN + MuJoCo simulation, learning, benchmarks | `conda activate nengo-mujoco && python scripts/step3_reflex.py` |
| **Neurochip** | All constraint/quantization/firmware APIs | `docker-compose up` in `Neurochip/` |
| **Neurosim** | All 13 backend simulation/design APIs | `docker-compose up` in `Neurosim/` |

### Tier 2 — Needs 1–3 Issues to Unlock
| Module | Gap | Estimated effort |
|---|---|---|
| **Neurobench** | Wire CLI + add Dockerfile + write tests | ~2–3 issues (Milestone 6–8) |
| **neuro_toolkit** | Hardcode a few module launchers (call `docker-compose up` via subprocess) | ~1 issue |
| **Neurochip frontend** | Finish QuantizationExplorer, ConstraintReportCard, FlashPanel | ~2 issues (Phase 4 remainder) |

### Tier 3 — Significant Work Required
| Module | Gap |
|---|---|
| **Neurosim frontend** | Entire canvas UI (NS-D1–D5) — the hardest single frontend sprint |
| **Neurohub** | Service layer + all screens |
| **Neurosense** | Signal viewer, recording, spike encoding screens |

---

## Which Submodules Need the Most Focus for POC

```
Priority 1 (Unblock everything):
  neurocnl backend — ALREADY DONE. Just needs to be running.

Priority 2 (Make the launcher work):
  neuro_toolkit — wire ModuleProvider to call docker-compose up/down.
  Even 50 lines of subprocess code unlocks the entire demo flow.

Priority 3 (Complete the minimal demo loop):
  Neurosim frontend — NS-D1 (canvas) is the visual centrepiece.
  Without a canvas, there's no "wow" moment.

Priority 4 (Add depth to the demo):
  Neurobench CLI — lets you run a benchmark from one command.
  Neurochip frontend — shows the hardware deployment story.

Priority 5 (Full-stack completeness):
  Neurohub — useful only once the other apps are stable.
  Neurosense — requires physical hardware to be meaningful.
```

---

## Cross-Module Dependency Map

```
neurocnl lib ◄──────────── consumed by Neurosim (simulate/validate)
                            consumed by Neurobench (benchmark runner)
                            consumed by Neurochip (generates export formats)
                            consumed by Neuro-Dream-Hand (CNL specs)

Neuro-Dream-Hand lib ◄───── consumed by Neurobench (fault sweeper)
                             consumed by Neurochip (crossbar export)

Neurochip API ◄─────────── consumed by Neurobench (cross-target comparison)
                            consumed by Neurosim (NS-E2 "Open in NeuroChip")

Neurosense API ◄────────── consumed by Neurobench (encoding comparison)

All app /health APIs ◄────── consumed by Neurohub (dashboard aggregation)

nmtk_ui_core Flutter pkg ◄─ consumed by neuro_toolkit + neurocnl/frontend

neuro_toolkit ◄──────────── orchestrates + WebViews all modules
```

---

## Test Coverage Summary

| Module | Tests | Status |
|---|---|---|
| neurocnl | 305 | ✅ All passing |
| Neuro-Dream-Hand | 130 | ✅ All passing (1 optional skipped) |
| Neurohub | 27 | ✅ Projects CRUD only |
| Neurosim | ~6 files | ⚠️ Style checks pass; full count unconfirmed |
| Neurochip | ~3 files | ⚠️ Pass count unconfirmed |
| Neurosense | 1 file | ⚠️ Minimal |
| Neurobench | 0 | ❌ Zero tests |
| neuro_toolkit | 0 | ❌ Zero tests |
| nmtk_ui_core | 0 | ❌ Zero tests |

---

## Global Issue Queue Progress

Based on `issue order.md` (72 total issues):

| Module group | Total issues | Completed | Remaining |
|---|---|---|---|
| NMTK / neurocnl / NDH / nmtk_ui_core | 30 | ~28 | NMTK-21 (ui-core components) + Phase 8 BrainFlow |
| Neurochip | 11 | ~8 | NC-p4 (3 frontend widgets) + NC-p5 (testing) |
| Neurosense | 8 | 1 (NSe-DM1) | 7 remaining (DM2, DM3, SA1, SA2, RS1, SE1, SE2, RS2) |
| Neurosim | 12 | 7 (backend) | 5 remaining (NS-D1–D5 canvas frontend) |
| Neurobench | 11 | ~5 (services) | 6 remaining (CLI, Docker, tests, frontend) |
| Neurohub | 10 | ~1 (projects) | 9 remaining (services + all frontend) |
| **Total** | **72** | **~50** | **~22 remaining** |
