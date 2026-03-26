# NeuroMorphicToolKit — Status Update (26 March 2026)

## 1. Executive Summary

The NMTK project is at approximately **~90% POC readiness** — a meaningful improvement from the ~85% reported on 25 March. The key advances since the last audit are:

- **CDD contracts and property-based tests are now deployed** into most modules (not just described in the pipeline README). neurocnl, Neurochip, Neurosense, Neurohub, Neurosim, Neurobench, and Neuro-Dream-Hand all have working `contracts/` directories with Pydantic models and `properties/` test directories with Hypothesis-based tests.
- **CI pipelines are mature** — all 7 modules now have CI workflows (correcting the 25 March report that Neurohub had no CI; it now has `neurohub-ci.yml`).
- **Frontend code is substantially larger than earlier estimates** across Neurohub, Neurosense, and Neurochip — these are full implementations, not stubs.
- **Root docker-compose.yml includes all 7 backend services** with healthchecks and network configuration.

The remaining gaps are: **5 empty Neurobench frontend widget files**, **5 stub backend services in Neurobench**, **Neurosense docker-compose.yml unconfigured** (contains only version string), **Neurohub docker-compose.yml still missing**, **Neurosim preview/sweep use mock data**, and **no CI for the nmtk launcher** itself.

---

## 2. Task Tracking State

All `issues/` directories across modules are **empty** except for `nmtk/neuro_toolkit/issues/` which has 5 well-defined issues. The previous `issues-archive/` directories and `*-Tasks.md` files from earlier reports are superseded. New canonical issue files are being created alongside this report.

---

## 3. Infrastructure & CI/CD

### Root docker-compose.yml
✅ **7 services defined**: neurocnl (8000), neurocnl-physics (8006, physics profile), neurosim (8001), neurochip (8002), neurobench (8003), neurosense (8004), neurohub (8005). All with healthchecks, `unless-stopped` restart policy, on `nmtk-network`.

### GitHub Actions Workflows (Root)
18 workflow files in `.github/workflows/`:
- **Core CI**: `ci.yml` (15K+ LOC, comprehensive multi-module pipeline)
- **CDD Pipeline**: `contract-verification.yml`, `cdd-pbt-module-ci.yml`, `issue-sync.yml`
- **Automation**: `auto-merge-agents.yml`, `ci-failure-fix-agent.yml`, `auto-merge-jules-prs.yml`, `ci-failure-fix.yml`
- **Operations**: `health-check.yml`, `integration-test.yml`, `pr-labeler.yml`, `release-promote.yml`, `scaffold-module.yml`, `stale-branches.yml`, `submodule-sync.yml`
- **Agent workflows**: `bug-fixer.yml`, `feature-builder.yml`, `unblocked-issues.yml`

### Unified CDD+PBT Pipeline
All 7 modules have `module.json` manifests and `.issue-state.json` tracking files. Issues have been generated for all modules. AGENTS.md and GUARDRAILS.md exist for neurocnl and neuro-dream-hand; other modules still need them.

---

## 4. Per-Module Status (26 March)

### neurocnl (97% ready) ⬆ from 95%

| Aspect | Status | Detail |
|--------|--------|--------|
| **Backend** | ✅ Production-ready | 8 routers + 5 prosthetic sub-routers, 7 services, 7 schema files, rate limiting, request ID middleware |
| **Core Library** | ✅ Complete | CNL parser, L1/L2 validators, Nengo generator, 6 exporters (NIR, Loihi, Lava, NeuroML, SpiNNaker, C-header), 6 converters, spike encoding, visualization |
| **Frontend** | ✅ Comprehensive | 5 screens, 15 widgets (all implemented), 11 providers, 12 models, 4 services. ~8-10K LOC |
| **Tests** | ✅ Excellent | ~15 backend test files, ~25 library test files, 4 frontend test files. 50+ test functions, all substantive |
| **Contracts/PBT** | ✅ Complete | 3 contract files (pipeline, neuron_params, hardware_export) with 13+ Pydantic models. Property tests with Hypothesis |
| **Docker** | ✅ Ready | Backend + Frontend Dockerfiles, multi-stage frontend build (Flutter → nginx) |
| **CI** | ✅ Active | `ci.yml` with pytest matrix (Python 3.11/3.12), plus 5 automation workflows |

**Remaining**: No known blockers. Minor edge-case invariant expansion possible.

---

### Neurosim (80% ready) ⬆ from 75%

| Aspect | Status | Detail |
|--------|--------|--------|
| **Backend** | ✅ Functional | 8 routers (components, templates, validation, generation, preview, sweep, export, projects), 4 services, 8 schema files, 13 component manifests (JSON) |
| **Frontend** | ⚠️ Partial | 1 screen (CanvasScreen), 5 widgets (network_canvas ~250 LOC with drag/drop/zoom, cnl_editor, component_library_sidebar, property_panel, export_dialog), 5 providers, 9 models (with build_runner codegen). ~1,200 LOC |
| **Tests** | ✅ Excellent | 14 Python test files (46+ functions) + 3 Dart tests. 15+ property tests with Hypothesis. Integration tests cover full pipeline |
| **Contracts/PBT** | ✅ Complete | `design_contracts.py` with Layer 1 invariants used by schemas throughout |
| **Docker** | ✅ Ready | Dockerfile + docker-compose.yml with hot-reload volume |
| **CI** | ✅ Active | 3-job CI (lint, type-check, test) with ruff, mypy strict, pytest+coverage (60% target) |

**Remaining**:
- Preview runner returns mock data (no actual Nengo simulation in preview)
- Sweep runner uses mock preview
- Export formats (Python, C, NeuroML, SVG) return template strings
- Project storage is in-memory (not persistent)
- Only 1 screen — needs additional screens for sweep, export, comparison views

---

### Neurosense (85% ready) ⬆ from 80%

| Aspect | Status | Detail |
|--------|--------|--------|
| **Backend** | ✅ Feature-complete | 9 routers (devices, encoding, export, nir, presets, quality, recording, sessions, stream), 8 services (device_manager, filter_pipeline, nir_service, pipeline_bridge, quality_analyzer, recording_service, replay_service, spike_encoder), 5 schema files |
| **Frontend** | ✅ Implemented | 3 screens, 9 widgets (all implemented: recording_controls, live_signal_viewer, device_selector, signal_quality_bar, spike_encoding_panel, export_dialog, preset_selector, replay_controls, pipeline_connector), 5 providers, 4 models. ~1,800-2,400 LOC |
| **Tests** | ✅ Good | 11 test files + 2 property test files. ~40-50 test functions with mocked BrainFlow hardware |
| **Contracts/PBT** | ✅ Complete | 6 contract files (device, encoding, performance, recording, signal, init). 2 Hypothesis property test files |
| **Docker** | ⚠️ Partial | Dockerfile works. **docker-compose.yml contains only `version: '3.8'`** (no services defined) |
| **CI** | ✅ Active | CI with lint, mypy strict, pytest, property tests, CDD-PBT reusable workflow |

**Remaining**:
- docker-compose.yml needs actual service definitions
- Hardware integration unverified on real OpenBCI boards
- Frontend-backend integration needs end-to-end verification

---

### Neurohub (80% ready) ⬆⬆ from 65%

| Aspect | Status | Detail |
|--------|--------|--------|
| **Backend** | ✅ Complete | 10 routers (activity, assets, config, dashboard, health, members, milestones, notes, projects, workflows), 8 services, 9 SQLAlchemy ORM models, 8 schema files. SQLite DB initialized on startup |
| **Frontend** | ✅ Comprehensive | 8 screens, 11 widgets (ALL implemented with real UI logic — activity_feed ~190 LOC, project_card ~45 LOC, etc.), 2 providers, 3 models, 2 services. ~3,000-4,000 LOC |
| **Tests** | ✅ Excellent | 15 Python test files (60 functions), 5 Dart test files. 5 property-based test files (bundle, orchestration, project, workflow). Test fixtures with in-memory SQLite |
| **Contracts/PBT** | ✅ Complete | 4 contract files (bundle, project, orchestration, workflow) with comprehensive Pydantic validation |
| **Docker** | ⚠️ Gap | Dockerfile exists (multi-stage, non-root). **No docker-compose.yml** |
| **CI** | ✅ Active | `neurohub-ci.yml` with backend (lint, mypy, pytest, property tests) + frontend (Flutter analyze+test) jobs. [CORRECTION from 25 March: CI now exists] |

**Remaining**:
- docker-compose.yml needs to be created
- Project export/import endpoints return empty dicts (stubbed)
- Dart test coverage is lighter than Python tests

---

### Neurochip (90% ready) ⬆⬆ from 70%

| Aspect | Status | Detail |
|--------|--------|--------|
| **Backend** | ✅ Complete | 8 routers (analysis, deployments, estimation, export, faults, quantization, serial, targets), 9 services (all implemented with real logic — constraint_analyzer ~115 LOC, quantizer ~85 LOC with scientific model), 6 schema files, 5 hardware target profiles (Teensy, Loihi2, BrainScales, SpiNNaker, Akida) |
| **Frontend** | ✅ Complete | 4 screens, 9 widgets (ALL implemented — quantization_explorer ~200 LOC with debouncing, constraint_report_card, deployment_log_table, fault_injection_panel, firmware_generator_panel, flash_progress_indicator, power_latency_panel, target_comparison_table, target_selector), 2 providers, 6 models, 1 service (~100 LOC). ~2,150 LOC |
| **Tests** | ✅ Excellent | 14 unit test files + 3 property test files (10+ property tests covering quantization bounds, deployment manifests, fault rates, latency monotonicity, hardware memory fit). 5 Dart test files |
| **Contracts/PBT** | ✅ Complete | 5 contract files (deployment, estimation, fault, hardware, quantization) |
| **Docker** | ✅ Ready | Dockerfile (Poetry-based) + docker-compose.yml with volume mount |
| **CI** | ✅ Active | CI with ruff, mypy strict, pytest. 6 workflows total |

**Remaining**: No major blockers. Serial port flashing untested on real hardware.

---

### Neurobench (70% ready) ⬆ from 60%

| Aspect | Status | Detail |
|--------|--------|--------|
| **Backend** | ⚠️ Mixed | 8 routers functional. 9 services but **5 are stubs** (report_generator ~23 LOC, fault_sweeper ~28 LOC, perturbation_sweeper, encoding_comparator ~26 LOC, target_comparator). 4 working services (benchmark_runner ~110 LOC with neurocnl integration, benchmark_loader, result_store with SQLite, diff_engine). 5 built-in benchmark definitions (JSON) |
| **Frontend** | ⚠️ Partial | 4 screens, 9 widgets but **5 are empty files** (robustness_curve_chart, perturbation_curve_chart, target_comparison_grid, report_builder, run_history_timeline — all 0 bytes). 4 implemented widgets (benchmark_catalog, results_summary_card, metric_diff_table, baseline_selector). 2 models, 2 providers, 1 service. ~600-800 LOC |
| **Tests** | ✅ Good | 11 test files (34 functions), 3 property test files with custom Hypothesis strategies |
| **Contracts/PBT** | ✅ Complete | 4 contract files (benchmark, regression, robustness, comparison) |
| **Docker** | ✅ Ready | Dockerfile + docker-compose.yml (port 8003, healthcheck) |
| **CI** | ✅ Comprehensive | 4-job CI (backend-lint, backend-cdd-pbt, backend-tests, frontend) with dependency gating |

**Remaining**:
- 5 empty frontend widget files need implementation
- 5 stub backend services need real logic
- Some router endpoints return 501 Not Implemented

---

### Neuro-Dream-Hand (95% ready) ⬆ from 93%

| Aspect | Status | Detail |
|--------|--------|--------|
| **Core Library** | ✅ Mature | 38 Python files across 5 packages (core, hardware, learning, analytics, experiments). ~6,500-8,000 LOC. Complete Nengo SNN simulation, MuJoCo physics, PES/BCM learning, sleep consolidation, quantization analysis |
| **Tests** | ✅ Excellent | 29 test files (25 unit + 2 property + 1 contract + 1 conftest). ~100-150 test functions. Coverage target ≥60% |
| **Scripts** | ✅ Complete | 13 experimental step scripts + 7 utility scripts. Full progression from box-drop → gripper → reflex → sleep → online-learning → quantization → sim-to-real |
| **Examples** | ✅ Complete | 6 example scenarios with paired .py + .ipynb files + hardware Teensy demo |
| **Contracts/PBT** | ✅ Complete | Hardware contracts (GripCommand, SensorFrame, FaultInjection, SerialBridge, EMGSpikeOutput, CrossbarExport) + Experiment contracts (HITLLatency, DropTest, ExperimentManifest). Hypothesis property tests with CI/dev profiles |
| **CI** | ✅ Active | 8 workflows including main CI (contracts → properties → unit tests), integration tests, agent automation |
| **Type Safety** | ✅ Strong | `disallow_untyped_defs = true` in mypy, ruff T201 print detection |

**Remaining**:
- No Docker containerization (library, not a service)
- Hardware I/O code (serial, EMG, Loihi export) untested on real hardware
- Lava bridge is skeletal (~100 LOC)

---

### nmtk Launcher (85% ready) ⬆ from 80%

| Aspect | Status | Detail |
|--------|--------|--------|
| **neuro_toolkit App** | ✅ Functional | 4 screens (dashboard, catalog, tool_view with WebView, python_setup), 1 widget (module_tab_bar), 2 services (ProcessManager with health checks, BundleManager), 1 provider (ModuleProvider with ChangeNotifier), GoRouter routing. 17 Dart files |
| **nmtk_ui_core** | ✅ Complete | 6 reusable widgets (buttons, energy_chart, quantization_table, sparkline, pipeline_stepper, navigation_rail), 3 models, 1 theme module (light/dark with design tokens). 14 Dart files. Zero external dependencies |
| **Tests** | ✅ Good | 6 neuro_toolkit test files (widget, catalog, dashboard, process_manager, module_provider, **launcher_e2e** — real integration test), 3 nmtk_ui_core test files |
| **Module Config** | ✅ Complete | `modules.json` defines all 7 modules with ports, descriptions, install commands |
| **Issues** | ✅ Active | 5 issue files (E2E test, expand coverage, macOS DMG, Linux AppImage, Windows installer) |
| **CI** | ❌ Missing | No dedicated CI workflow for the launcher |

**Remaining**:
- No CI workflow for launcher Flutter tests
- Installer validation across platforms untested
- nmtk_ui_core has 1 placeholder test

---

## 5. Cross-Cutting Comparison (25 March → 26 March)

| Module | 25 March | 26 March | Delta | Key Change |
|--------|----------|----------|-------|------------|
| neurocnl | 95% | 97% | +2% | Contracts/properties deployed in-module, no import errors |
| Neurosim | 75% | 80% | +5% | Contracts integrated, property tests confirmed, 46+ tests |
| Neurosense | 80% | 85% | +5% | 6 contract files deployed, all widgets confirmed implemented |
| Neurohub | 65% | 80% | +15% | CI workflow exists, 60 test functions, 4 contract files, comprehensive frontend confirmed |
| Neurochip | 70% | 90% | +20% | All widgets implemented, 5 contract files, 10+ property tests, clean codebase |
| Neurobench | 60% | 70% | +10% | Contracts/PBT complete, but frontend widgets still empty |
| Neuro-Dream-Hand | 93% | 95% | +2% | Clean codebase confirmed, proper logging throughout |
| nmtk Launcher | 80% | 85% | +5% | E2E test exists, 5 tracked issues |
| **Overall** | **~85%** | **~90%** | **+5%** | |

---

## 6. Corrections from Previous Reports

| Claim (25 March) | Actual (26 March) |
|-------------------|-------------------|
| Neurohub has no CI at all | ✅ `neurohub-ci.yml` exists with backend + frontend jobs |
| Neurochip widgets "may need wiring/completion" | ✅ All 9 widgets are fully implemented with real UI logic |
| Neurosense "0 tests" (from earlier reports) | ✅ 11 test files + 2 property test files (~40-50 functions) |
| Neurohub frontend "238 LOC scaffolds" | ✅ ~3,000-4,000 LOC with 8 screens, 11 implemented widgets |
| Neurobench frontend "164 LOC scaffolds" | ⚠️ ~600-800 LOC — better than reported but 5/9 widgets still empty (0 bytes) |
| Pipeline README claims contracts exist as Python files | ⚠️ Partially corrected — contracts DO now exist in most modules in their actual source trees, though the README directory structure still shows some files that don't exist in the unified-dev-pipeline/ directory itself |

---

## 7. Priority Work Remaining

### P0 — Critical for POC Demo
1. **Neurohub docker-compose.yml** — Only module without compose orchestration
2. **Neurosense docker-compose.yml** — File exists but contains only version string
3. **Neurobench: 5 empty widget files** — robustness_curve_chart, perturbation_curve_chart, target_comparison_grid, report_builder, run_history_timeline

### P1 — Important for Completeness
4. **Neurobench: 5 stub backend services** — report_generator, fault_sweeper, perturbation_sweeper, encoding_comparator, target_comparator
5. **Neurosim: Replace mock preview/sweep/export** — Currently returns template/mock data
6. **Neurosim: Additional screens** — Only 1 screen (CanvasScreen) exists
7. **Neurohub: Implement project export/import** — Endpoints return empty dicts

### P2 — Quality & Polish
8. **nmtk launcher CI workflow** — No dedicated CI for launcher tests
9. **AGENTS.md + GUARDRAILS.md** — Only neurocnl and neuro-dream-hand have these; 5 modules need them
10. **Neurosim project persistence** — In-memory dict should use SQLite or file-based storage
11. **Root docker-compose validation** — Full `docker compose up` test needed

### P3 — Hardware Validation
12. **Neuro-Dream-Hand hardware I/O** — Serial, EMG, Loihi untested on physical devices
13. **Neurochip serial flashing** — Untested on real Teensy
14. **Neurosense OpenBCI integration** — Untested on real boards

---

## 8. Active Issue Counts Per Module (26 March)

| Module | Issues Created | Key Priorities |
|--------|---------------|----------------|
| **neurocnl** | 3 | Edge-case invariants, expand frontend tests, deprecate old automation workflows |
| **Neurosim** | 5 | Replace mock services (P1), add screens, persist projects, verify canvas API wiring |
| **Neurosense** | 3 | Fix docker-compose (P0), verify hardware integration, expand Dart tests |
| **Neurohub** | 4 | Create docker-compose (P0), implement export/import, expand Dart tests, add AGENTS.md |
| **Neurochip** | 2 | Verify serial flash on hardware, add AGENTS.md + GUARDRAILS.md |
| **Neurobench** | 4 | Implement empty widgets (P0), implement stub services (P1), verify screens, add AGENTS.md |
| **Neuro-Dream-Hand** | 3 | Validate hardware I/O, strict mypy, Lava bridge expansion |
| **nmtk launcher** | 5 (existing) | E2E test, coverage, installer validation (3 platforms) |
| **Root (cross-cutting)** | 4 | Docker-compose validation, launcher CI, deprecated workflow cleanup, pipeline README fix |
| **TOTAL** | **33 issues** | |

---

## 9. Summary

The NMTK ecosystem has matured significantly. **All 7 modules have functional backends, CDD contracts, property-based tests, and CI pipelines.** The biggest improvement since March 25 is the recognition that Neurochip, Neurohub, and Neurosense are much more complete than previously reported — code inspection confirms fully implemented frontends and comprehensive test suites.

The remaining ~10% is concentrated in:
- **Neurobench** (empty widget files and stub services)
- **Docker gaps** (Neurohub compose missing, Neurosense compose unconfigured)
- **Mock data** in Neurosim preview/sweep/export
- **Hardware validation** across Neuro-Dream-Hand, Neurochip, and Neurosense (which requires physical devices)

The project is well-positioned for a POC demonstration once the P0 items are resolved.
