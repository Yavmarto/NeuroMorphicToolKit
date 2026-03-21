# NeuroMorphicToolKit — Tasks to 100% POC Readiness

**Date:** 2026-03-21
**Current Readiness:** ~78%
**Target:** 100% — fully demo-able, installable, and reproducible

---

## TIER 1 — Critical Blockers (Must fix before any demo)

### T1-1: Fix Neurochip Dockerfile build context mismatch
- **Problem:** Root `docker-compose.yml` sets `context: ./Neurochip` and `dockerfile: Dockerfile`. The Dockerfile does `COPY neurochip/pyproject.toml .` but the actual path is `Neurochip/neurochip/pyproject.toml` (nested). The `poetry install` command runs inside the `neurochip/` subdirectory. The COPY path and working directory in the Dockerfile must match the actual repo structure.
- **Fix:** Verify and correct the Dockerfile COPY directives to match the actual `Neurochip/` directory layout. Ensure `poetry.lock` is also copied if it exists.
- **Effort:** 30 min
- **Verify:** `docker build -t neurochip-test ./Neurochip`

### T1-2: Fix Neurobench Dockerfile build context mismatch
- **Problem:** Same issue as Neurochip. Dockerfile references `neurobench/pyproject.toml` but the nested structure may cause COPY failures.
- **Fix:** Same approach — verify and correct COPY directives.
- **Effort:** 30 min
- **Verify:** `docker build -t neurobench-test ./Neurobench`

### T1-3: Create Neurohub docker-compose.yml
- **Problem:** Neurohub has a Dockerfile but no `docker-compose.yml` for standalone local development. The root `docker-compose.yml` references it, but developers working on Neurohub alone have no compose file.
- **Fix:** Create `Neurohub/docker-compose.yml` with:
  - Single backend service on port 8005
  - Volume mount for live development
  - Healthcheck on `/api/neurohub/health`
  - `PYTHONUNBUFFERED=1` environment
- **Effort:** 15 min
- **Verify:** `cd Neurohub && docker-compose up --build`

### T1-4: Fix Neurosense docker-compose.yml (currently stub)
- **Problem:** `Neurosense/docker-compose.yml` contains only `version: '3.8'` — no services defined.
- **Fix:** Populate with a backend service definition matching the Dockerfile (port 8004, volume mount, healthcheck).
- **Effort:** 15 min
- **Verify:** `cd Neurosense && docker-compose up --build`

### T1-5: Validate root docker-compose.yml startup (all 7 services)
- **Problem:** The root `docker-compose.yml` has never been tested end-to-end. Build contexts, healthchecks, profiles, and inter-service dependencies are unvalidated.
- **Fix:** Run `docker-compose up --build` and fix all issues. Test each profile:
  - Default profile (neurocnl, neurosim, neurochip)
  - `--profile full` (all 7 services)
  - `--profile physics` (neurocnl-physics variant)
- **Effort:** 2-4 hours (expect iterative fixes)
- **Verify:** All 7 services pass healthchecks, `scripts/validate_docker_compose.sh` passes, `scripts/demo_smoke_test.sh` passes

### T1-6: End-to-end launcher flow test
- **Problem:** The neuro_toolkit launcher has real process management but the full flow (install module → launch backend → WebView loads UI) has not been tested on a real machine.
- **Fix:** Test on macOS:
  1. `cd nmtk/neuro_toolkit && flutter run -d macos`
  2. Browse catalog → Install neurocnl → Launch → Verify WebView loads
  3. Test stop/restart cycle
  4. Test multiple modules running simultaneously
- **Effort:** 1 day
- **Verify:** Can complete the full demo walkthrough from DEMO_WALKTHROUGH.md using the launcher

---

## TIER 2 — Frontend Integration (Makes demo impressive)

### T2-1: Neurosim — Wire canvas interactions to backend API
- **Problem:** Canvas exists (1,910 LOC) with CustomPainter, drag-and-drop, node rendering. But the integration between canvas actions and backend API endpoints (parse, validate, simulate, export) may not be fully wired.
- **Fix:**
  1. Verify `ApiClient` methods (fetchComponents, runPreview, exportGraph) actually call backend
  2. Test: drag components → form connections → click Simulate → see results
  3. Wire CNL editor sync (canvas changes → CNL text → backend validate)
- **Effort:** 2-3 days
- **Verify:** Can create a simple 2-neuron network on canvas, simulate it, and see preview results

### T2-2: Neurosense — Integration test frontend against backend
- **Problem:** Frontend grew to 2,249 LOC with 4 providers and enhanced viewers. Needs validation that providers correctly call backend API and display real data.
- **Fix:**
  1. Start backend: `cd Neurosense/neurosense && uvicorn app.main:app --port 8004`
  2. Run frontend: `cd Neurosense/frontend && flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8004`
  3. Test: device discovery → filter config → recording → spike encoding → quality display
  4. Fix any API contract mismatches
- **Effort:** 1-2 days
- **Verify:** Can see mock device data flowing through the UI pipeline

### T2-3: Neurochip — Complete remaining frontend widgets
- **Problem:** Frontend has ApiClient, HardwareProfile model, and Riverpod providers (1,198 LOC). But key widgets are likely still stubs: QuantizationExplorer, ConstraintReportCard, FirmwareGeneratorPanel, FlashProgressIndicator.
- **Fix:**
  1. Implement QuantizationExplorer: slider for bit-width, live preview of quantization effects
  2. Implement ConstraintReportCard: display constraint analysis results from backend
  3. Wire FirmwareGeneratorPanel to backend's teensy_generator and loihi_generator endpoints
  4. Add FlashProgressIndicator for deployment feedback
- **Effort:** 2-3 days
- **Verify:** Can select a hardware target, run quantization, see constraints, generate firmware

### T2-4: Neurohub — Build functional dashboard frontend
- **Problem:** Frontend is 238 LOC of scaffolds. DashboardScreen is literally a few lines. 8 screen files and 11 widget files are all minimal.
- **Fix:**
  1. Implement DashboardScreen: show grid of module health statuses (call each module's /health)
  2. Implement SuiteHealthBar: visual status of all running services
  3. Implement ActivityFeed: recent actions across modules
  4. Wire ProjectCard and project CRUD to backend API
- **Effort:** 3-5 days
- **Verify:** Dashboard shows live health status of running modules

### T2-5: Add demo screenshots to DEMO_WALKTHROUGH.md
- **Problem:** Walkthrough is text-only. Screenshots would make it self-explanatory.
- **Fix:** Capture and add screenshots of:
  1. Launcher catalog view
  2. Module installation progress
  3. WebView showing neurocnl UI
  4. CNL editor with sample spec
  5. Simulation results
- **Effort:** 1 day
- **Verify:** A new developer can follow the walkthrough without confusion

---

## TIER 3 — Testing & Quality (Production confidence)

### T3-1: Add Dart tests to Neurosense frontend
- **Problem:** 24 Dart files, 2,249 LOC, 0 test files.
- **Fix:** Add widget tests for key screens (DeviceSelector, SignalViewer, RecordingControls) and unit tests for providers.
- **Effort:** 1-2 days

### T3-2: Add Dart tests to Neurochip frontend
- **Problem:** 23 Dart files, 1,198 LOC, 0 test files.
- **Fix:** Add widget tests for TargetSelector and unit tests for ApiClient/providers.
- **Effort:** 1 day

### T3-3: Add Dart tests to Neurohub frontend
- **Problem:** 20 Dart files, 238 LOC, 0 test files.
- **Fix:** Add basic widget tests as frontend is built out.
- **Effort:** 1 day (after T2-4)

### T3-4: Expand neuro_toolkit tests
- **Problem:** Only 2 test files for 1,416 LOC. ProcessManager (284 LOC) and ModuleProvider (165 LOC) are untested.
- **Fix:** Add unit tests for ProcessManager (mock process spawning), ModuleProvider (state transitions), and widget tests for Catalog and Dashboard screens.
- **Effort:** 1-2 days

### T3-5: Wire Neurobench real benchmark runner
- **Problem:** BenchmarkRunner generates random job IDs instead of running real benchmarks. 5 benchmark definitions exist in JSON but aren't executed.
- **Fix:** Implement actual benchmark execution using neurocnl library calls. Wire the result_store to persist real results. Connect CLI entrypoint.
- **Effort:** 2-3 days

### T3-6: Neurosim — Add Python integration tests
- **Problem:** 12 test files exist but canvas-to-backend integration is untested.
- **Fix:** Add integration tests that exercise the full graph → CNL → simulate → preview pipeline via API.
- **Effort:** 1 day

---

## TIER 4 — Packaging & Distribution (Real-world deployment)

### T4-1: Validate macOS DMG installer
- **Problem:** `nmtk/installer/macos/create-dmg.sh` exists but has never been tested. It builds from Flutter release artifacts.
- **Fix:**
  1. Build Flutter app: `cd nmtk/neuro_toolkit && flutter build macos --release`
  2. Run DMG creator: `cd nmtk/installer/macos && bash create-dmg.sh`
  3. Test: mount DMG → drag to Applications → launch
- **Effort:** 1 day
- **Verify:** App launches from /Applications on a clean macOS machine

### T4-2: Validate Linux AppImage installer
- **Problem:** `nmtk/installer/linux/appimage.sh` exists but untested.
- **Fix:** Test on Ubuntu 22.04+ (VM or CI).
- **Effort:** 1 day

### T4-3: Fix Windows installer scope
- **Problem:** `nmtk/installer/windows/setup.iss` only builds the neurocnl frontend, not the full neuro_toolkit launcher.
- **Fix:** Update Inno Setup script to build from `nmtk/neuro_toolkit/build/windows/` and include all module assets.
- **Effort:** 1 day

### T4-4: Create one-command development setup script
- **Problem:** Setting up the full dev environment requires manual steps across 7+ directories.
- **Fix:** Create `scripts/dev-setup.sh` that:
  1. Inits and updates all git submodules
  2. Creates a shared Python venv or per-module venvs
  3. Installs all Python backends in editable mode
  4. Runs `flutter pub get` in all frontend directories
  5. Verifies all health endpoints
- **Effort:** 1 day

### T4-5: Add root-level pre-commit hooks
- **Problem:** neurocnl and Neurohub have per-module pre-commit configs. No root-level enforcement exists.
- **Fix:** Create root `.pre-commit-config.yaml` with ruff, mypy, and flutter analyze hooks scoped to relevant paths.
- **Effort:** 0.5 day

---

## TIER 5 — Documentation & Polish (Professional finish)

### T5-1: Create comprehensive SETUP_GUIDE.md
- **Problem:** Desktop_Guide.md is outdated (references old port assignments, no Docker instructions, no launcher workflow).
- **Fix:** Write a new guide covering Docker setup, manual setup, launcher usage, and developer workflow. (See companion file.)
- **Effort:** Done (companion task)

### T5-2: Update README.md with current architecture
- **Problem:** README.md describes the vision but doesn't reflect the current 7-module architecture, Docker orchestration, or launcher capabilities.
- **Fix:** Update with current module list, port assignments, architecture diagram, and quick-start instructions.
- **Effort:** 0.5 day

### T5-3: Create CONTRIBUTING.md
- **Problem:** No contributor guide exists. Module structure, testing conventions, and PR workflow are undocumented.
- **Fix:** Document module structure, coding standards (ruff, mypy --strict), testing requirements, PR process, and submodule workflow.
- **Effort:** 0.5 day

### T5-4: Create ARCHITECTURE.md
- **Problem:** No single document describes the system architecture, inter-module dependencies, data flow, or communication patterns.
- **Fix:** Document the launcher → backend → frontend architecture, API contracts, shared libraries, and module lifecycle.
- **Effort:** 1 day

---

## Task Summary

| Tier | Tasks | Total Effort | Impact |
|------|-------|-------------|--------|
| **TIER 1** — Critical Blockers | 6 tasks | ~2-3 days | Unblocks demo |
| **TIER 2** — Frontend Integration | 5 tasks | ~10-14 days | Makes demo impressive |
| **TIER 3** — Testing & Quality | 6 tasks | ~8-11 days | Production confidence |
| **TIER 4** — Packaging & Distribution | 5 tasks | ~4-5 days | Real-world deployment |
| **TIER 5** — Documentation & Polish | 4 tasks | ~2-3 days | Professional finish |
| **TOTAL** | **26 tasks** | **~26-36 days** | **100% POC readiness** |

---

## Recommended Execution Order

**Week 1: Unblock and validate**
- T1-1, T1-2, T1-3, T1-4 (Docker fixes — 1 day)
- T1-5 (Validate root docker-compose — 1 day)
- T1-6 (End-to-end launcher test — 1 day)
- T5-1 (Setup guide — done)
- T4-4 (Dev setup script — 1 day)

**Week 2: Frontend integration sprint**
- T2-1 (Neurosim canvas wiring — 2-3 days)
- T2-2 (Neurosense integration — 1-2 days)
- T2-3 (Neurochip widgets — 2-3 days)

**Week 3: Dashboard + testing**
- T2-4 (Neurohub dashboard — 3-5 days)
- T3-1, T3-2 (Dart tests for Neurosense + Neurochip — 2-3 days)

**Week 4: Polish and ship**
- T3-4, T3-5 (Launcher tests + Neurobench runner — 3-5 days)
- T4-1, T4-2, T4-3 (Installer validation — 2-3 days)
- T2-5, T5-2, T5-3, T5-4 (Documentation — 2-3 days)
- T4-5, T3-3, T3-6 (Pre-commit, remaining tests — 2 days)
