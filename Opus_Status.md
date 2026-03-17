# NeuroMorphicToolKit — Complete Status Report

**Generated:** 2026-03-17
**Branch:** dev
**Assessor:** Claude Opus 4.6

---

## Executive Summary

The NeuroMorphicToolKit (NMTK) is a multi-module neuromorphic computing platform consisting of a Flutter desktop launcher app and 7 specialized Python+Flutter submodules. Two submodules (neurocnl and Neuro-Dream-Hand) are mature, production-quality Python libraries. The remaining five (Neurosim, Neurochip, Neurobench, Neurosense, Neurohub) are at varying stages of backend/frontend implementation. The Flutter launcher app (`neuro_toolkit`) is a Phase 1 shell with working navigation but mock installation logic.

**POC Readiness: ~45%** — The core Python libraries work. The desktop app launches but cannot actually orchestrate the submodule backends yet.

---

## Module Status Overview

| Module | Role | Backend | Frontend | Tests | Overall | POC Critical? |
|--------|------|---------|----------|-------|---------|---------------|
| **neuro_toolkit** | Desktop launcher | N/A | 90% shell | Broken | 40% | YES |
| **nmtk_ui_core** | Shared Flutter theme | N/A | 100% | None | 90% | YES |
| **neurocnl** | CNL parser + SNN generator | 95% | 30% scaffold | 319 tests | 85% | YES |
| **Neuro-Dream-Hand** | Prosthetic SNN sim | 95% | N/A | 130 tests | 90% | NO (demo) |
| **Neurosim** | Visual SNN designer | 90% API | 0% (none) | 6 files | 50% | YES |
| **Neurochip** | Hardware deployment | 65% | 40% scaffold | 3 files | 55% | NO |
| **Neurobench** | Benchmarking | 35% stubs | 40% scaffold | None | 35% | NO |
| **Neurosense** | Biosignal acquisition | 80% | 50% | 1 file | 65% | NO |
| **Neurohub** | Dashboard orchestrator | 75% + DB | 30% scaffold | 2 files | 55% | NO (later) |
| **nmtk** | Installer/docs | Scripts only | N/A | N/A | 20% | YES |

---

## Detailed Module Breakdown

### 1. neuro_toolkit (Flutter Desktop Launcher)

**Purpose:** The single entry point app. Users browse, install, and launch submodules from here.

**What Works:**
- `main.dart` with Provider state management
- DashboardScreen — lists installed modules with Launch/Delete buttons
- CatalogScreen — shows available modules with Install button and progress bar
- ToolViewScreen — mock terminal output for launched modules
- Bottom navigation between Dashboard and Catalog
- Depends on `nmtk_ui_core` for theming (ResponsiveScaffold, AppTheme)

**What Doesn't Work:**
- Installation is **mock only** — simulates download with a timer, no real module download
- No actual process orchestration — cannot start Python backends or Docker containers
- No WebView integration for displaying submodule UIs
- Test file is broken (references deleted `MyApp` class)
- 3 hardcoded modules only (Neuro-Dream-Hand, neurocnl, nmtk)

**Key Dependencies:** Flutter SDK >=3.6.0, provider ^6.1.5, nmtk_ui_core (local path)

**Files:** 6 Dart files in lib/

---

### 2. nmtk_ui_core (Shared Flutter Package)

**Purpose:** Shared theme, colors, typography, and layout components.

**What Works:**
- `app_theme.dart` — complete light/dark theme definitions (14KB)
- `ResponsiveScaffold` and `NavigationDestinationData` exported
- Used by neuro_toolkit as a path dependency

**What's Missing:** No widget tests.

---

### 3. neurocnl (CNL Parser + SNN Generator)

**Purpose:** Parse plain-English specs into validated Spiking Neural Networks.

**What Works (Python library — MATURE):**
- CNL parser: 13 neuron concepts, regex-based, 90+ parser tests
- Layer 1 validator: 16 biological invariants, 88+ tests
- Layer 2 validator: cross-sentence consistency, orphan detection
- Nengo generator: compiles specs to executable Nengo networks
- Assertion generator: auto-generates pytest from specs
- 5 export formats: NeuroML, C header, NengoLoihi, Lava, SpiNNaker
- Spike encoding: rate, temporal, delta
- Visualization: spike raster, membrane traces, network topology
- CLI: `neurocnl examples/slip_reflex.cnl` — full pipeline
- Version 0.3.0, 6,545 LOC, 319 tests, CI on GitHub Actions

**What Works (FastAPI backend):**
- All API endpoints implemented: parse, validate, generate, simulate, export, templates
- Prosthetic endpoints: simulate, sleep, export, analysis, hardware
- Job system for async simulation
- 11 backend test files

**What Works (Flutter frontend):**
- Cross-platform project structure (web, macOS, Windows, Linux, iOS, Android)
- Basic scaffolding exists

**What Doesn't Work:**
- Frontend is mostly scaffolding — no functional IDE/Studio screens yet
- Backend and frontend are not integrated into the launcher app
- No Docker at root level

**Key Dependencies:** nengo>=3.2.0, numpy>=1.24.0, Python >=3.11

---

### 4. Neuro-Dream-Hand (Prosthetic SNN Simulation)

**Purpose:** Neuromorphic prosthetic hand control — simulation through to hardware deployment.

**What Works (MATURE — thesis-quality):**
- SNN reflex controller (Nengo): >95% object survival rate
- MuJoCo physics bridge: pinch and tripod grippers
- Sleep-based PES learning: progressive improvement over 30 simulated days
- Online continual learning (OCL): real-time adaptation in <5s
- Weight quantization: 4-bit to 32-bit sweep with degradation analysis
- Fault injection: dead neurons, stuck-at, Gaussian noise
- Power profiling: pJ/SOP estimation
- Crossbar HDF5 export for Loihi 2/Akida
- Serial bridge protocol for Teensy 4.0 (mock-tested)
- EMG streamer for OpenBCI Ganglion (mock-tested)
- EMG spike encoder: Butterworth filtering pipeline
- 13-step tutorial scripts (step1 through step13)
- 37 Python files, ~6,927 LOC, 130 tests, CI on GitHub Actions
- PID baseline controller for comparison
- Statistical validation with bootstrap CI and Wilcoxon tests

**What Doesn't Work:**
- Zero physical hardware validation (all mock-tested)
- Loihi 2 deployment requires Intel NxSDK (access-restricted)
- No Flutter frontend (standalone Python library)
- Energy estimates are modeled, not measured

**Key Dependencies:** nengo>=4.0.0, numpy, scipy, matplotlib, h5py, optional: mujoco, pyserial, brainflow

---

### 5. Neurosim (Visual SNN Designer)

**Purpose:** Drag-and-drop SNN design canvas with simulation preview.

**Backend (90% — Strong):**
- FastAPI with 29 Python files
- All 12 API endpoints implemented and functional:
  - Components catalog, templates, validation, CNL generation/parsing
  - Preview simulation, parameter sweeps, full simulation runs
  - Multi-format export, project save/load
- Real simulation logic with physics-based models
- 6 test files with comprehensive API coverage

**Frontend (0% — Missing):**
- No Flutter frontend exists at all
- No Dart files found

**Docker:** Dockerfile and docker-compose.yml present

**Gap:** This is a backend-only module. Needs a complete Flutter frontend or WebView integration.

---

### 6. Neurochip (Hardware Deployment Toolkit)

**Backend (65%):**
- FastAPI with 31 Python files
- Hardware profiles: Teensy 4.1, Loihi 2, Akida, SpiNNaker, BrainScaleS (JSON)
- Constraint analyzer: real compatibility checking
- Quantizer: actual mathematical models for bit-width analysis
- Teensy firmware generator: Jinja2 templates for C code generation
- Flash service: PlatformIO subprocess integration
- Fault runner, power estimator implemented
- 3 test files

**Frontend (40%):**
- 15 Dart files — structured UI scaffolds
- Screens: target gallery, analysis, comparison, deployment log
- Widgets: constraint report card, quantization explorer, fault injection panel
- Riverpod providers set up

**Docker:** Yes

---

### 7. Neurobench (Benchmarking Workbench)

**Backend (35% — Mostly Stubs):**
- FastAPI structure with 27 Python files
- All router/schema files exist but services are mocking logic
- BenchmarkRunner generates random job IDs instead of running real benchmarks
- SQLite result store implemented
- Benchmark JSON definitions exist (5 built-in benchmarks)

**Frontend (40%):**
- 17 Dart files — real UI scaffolds with Riverpod
- Benchmark catalog, results summary, metric diff table
- Robustness curve chart, run history timeline

**Docker:** Yes
**Tests:** None

---

### 8. Neurosense (Biosignal Acquisition)

**Backend (80% — Strong):**
- FastAPI with 26 Python files
- Device manager: comprehensive BrainFlow integration (245 LOC) with real async/await
- Filter pipeline: scipy.signal bandpass, notch, artifact rejection
- Spike encoder: wraps neurocnl encoding utilities
- Recording service: HDF5 session storage
- Quality analyzer: SNR, impedance, noise analysis
- 4 acquisition presets (EMG prosthetic, EEG alpha BCI, EOG gaze, tactile array)
- WebSocket streaming endpoints for raw/filtered/spike data

**Frontend (50%):**
- 20 Dart files — real implementations
- Device selector with full state management
- Models: device_info, preset, session, signal_quality
- Screens: acquisition, session browser, setup wizard

**Docker:** Yes
**Tests:** 1 file with integration tests

---

### 9. Neurohub (Suite Dashboard & Orchestrator)

**Backend (75% — Good):**
- FastAPI with 30 Python files
- SQLAlchemy ORM with 8 database models (Project, Milestone, Asset, Workflow, Activity, Config, Note, WorkflowRun)
- Full CRUD for projects
- Workflow engine: sequential step executor
- Activity collector: polls suite apps
- Health checker, config service
- 27 endpoint tests passing

**Frontend (30%):**
- 20 Dart files — partially implemented
- Dashboard screen is a stub (3 lines)
- Other screens have proper structure

**Docker:** No
**Tests:** 2 files

---

### 10. nmtk (Installer & Documentation)

**Purpose:** Cross-platform installer scripts and documentation.

**What Exists:**
- `installer/macos/create-dmg.sh` — macOS DMG creator
- `installer/linux/appimage.sh` — Linux AppImage creator
- `installer/windows/setup.iss` — Inno Setup script
- `scripts/setup.sh` and `scripts/setup.ps1` — environment setup
- Documentation: START_HERE.md, QUICK_START_GUIDE.md, ROADMAP.md
- Config: cliff.toml (changelog), codecov.yml (coverage)

**What's Missing:**
- No actual CLI tool
- Installer scripts may be outdated/untested
- No CI at root level

---

## POC Priority Analysis

### What Does a POC Look Like?

A minimal POC demonstrates: **Open the desktop app → Browse modules → Install neurocnl → Write a CNL spec → Validate → Generate SNN → See simulation results.**

### Critical Path to POC

```
Priority 1 (BLOCKERS — must fix)
├── neuro_toolkit: Replace mock install with real module backend startup
├── neuro_toolkit: Add WebView or embedded UI for launched modules
├── Neurosim: Build a minimal Flutter frontend (or use neurocnl's backend directly)
└── nmtk: Verify installer scripts work on macOS/Windows/Linux

Priority 2 (IMPORTANT — makes POC convincing)
├── neurocnl backend: Ensure it starts standalone with uvicorn
├── neuro_toolkit: Add all 7 modules to the catalog (currently only 3)
├── neuro_toolkit: Real process management (start/stop Python backends)
└── Neurosim: At minimum, a WebView pointing to the backend's /docs

Priority 3 (NICE TO HAVE — enhances demo)
├── Neurochip: Show quantization explorer working
├── Neuro-Dream-Hand: Show MuJoCo simulation video in app
├── Neurosense: Show live signal viewer
└── Neurohub: Show project dashboard aggregating status
```

### Modules Ranked by POC Focus Needed

| Rank | Module | Why | Effort |
|------|--------|-----|--------|
| 1 | **neuro_toolkit** | The launcher IS the POC — currently can't launch anything real | HIGH |
| 2 | **Neurosim** | Has no frontend at all — needs at least a WebView wrapper | MEDIUM |
| 3 | **neurocnl** | Backend works but needs to be startable from the launcher | LOW |
| 4 | **nmtk** | Installer scripts need testing for desktop deployment | MEDIUM |
| 5 | **Neurochip** | Already 60% — small push makes it demo-able | LOW |
| 6 | **Neurobench** | Stubs need real logic to show benchmarks | MEDIUM |
| 7 | **Neurohub** | Orchestration layer — useful but not POC-critical | LOW |
| 8 | **Neurosense** | Needs hardware — skip for POC | SKIP |
| 9 | **Neuro-Dream-Hand** | Python-only, no frontend needed for POC | SKIP |

---

## Desktop Deployment Guide

### Prerequisites

#### All Platforms
- **Flutter SDK** >= 3.6.0 (with desktop support enabled)
- **Dart SDK** >= 3.6.0 (included with Flutter)
- **Python** >= 3.11
- **Git** (for cloning)

#### macOS Additional
- Xcode >= 15.0 (for macOS desktop builds)
- CocoaPods (`sudo gem install cocoapods`)

#### Windows Additional
- Visual Studio 2022 with "Desktop development with C++" workload
- Windows 10 SDK

#### Linux Additional
- `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`

---

### Step 1: Clone and Setup

```bash
# Clone the repository
git clone <repo-url> NeuroMorphicToolKit
cd NeuroMorphicToolKit

# Verify Flutter desktop support
flutter doctor
flutter config --enable-macos-desktop    # macOS
flutter config --enable-windows-desktop  # Windows
flutter config --enable-linux-desktop    # Linux
```

### Step 2: Install the Shared UI Package

```bash
cd nmtk_ui_core
flutter pub get
cd ..
```

### Step 3: Build and Run the Launcher App

```bash
cd neuro_toolkit
flutter pub get

# Run in debug mode (your current platform)
flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d linux     # Linux

# Build a release binary
flutter build macos      # produces build/macos/Build/Products/Release/neuro_toolkit.app
flutter build windows    # produces build/windows/x64/runner/Release/neuro_toolkit.exe
flutter build linux      # produces build/linux/x64/release/bundle/neuro_toolkit
```

### Step 4: Set Up the neurocnl Python Backend

```bash
cd ../Neurocnl

# Create a virtual environment
python3.11 -m venv .venv
source .venv/bin/activate        # macOS/Linux
# .venv\Scripts\activate         # Windows

# Install the library
pip install -e ".[dev]"

# Verify the CLI works
neurocnl --help
neurocnl examples/slip_reflex.cnl

# Start the FastAPI backend
cd backend
pip install fastapi uvicorn
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
# API docs at http://localhost:8000/docs
```

### Step 5: Set Up Neuro-Dream-Hand (Optional — for simulation demos)

```bash
cd ../Neuro-Dream-Hand

# Create a conda environment (recommended for MuJoCo)
conda create -n nengo-mujoco python=3.11
conda activate nengo-mujoco

# Install with physics support
pip install -e ".[physics,dev]"

# Run the tutorial
python scripts/step1_hello_physics.py
python scripts/step3_reflex.py

# Run tests
pytest tests/test_neurodreamhand/ -v
```

### Step 6: Set Up Neurosim Backend (Optional)

```bash
cd ../Neurosim

python3.11 -m venv .venv
source .venv/bin/activate

pip install fastapi uvicorn pydantic
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
# API docs at http://localhost:8001/docs
```

### Step 7: Set Up Neurochip Backend (Optional)

```bash
cd ../Neurochip

python3.11 -m venv .venv
source .venv/bin/activate

cd neurochip
pip install fastapi uvicorn pydantic jinja2
uvicorn app.main:app --host 0.0.0.0 --port 8002 --reload
```

### Step 8: Set Up Neurobench Backend (Optional)

```bash
cd ../Neurobench

python3.11 -m venv .venv
source .venv/bin/activate

cd neurobench
pip install fastapi uvicorn pydantic
uvicorn app.main:app --host 0.0.0.0 --port 8003 --reload
```

### Step 9: Set Up Neurosense Backend (Optional)

```bash
cd ../Neurosense

python3.11 -m venv .venv
source .venv/bin/activate

cd neurosense
pip install fastapi uvicorn pydantic scipy h5py
# Note: brainflow needed only if connecting real hardware
uvicorn app.main:app --host 0.0.0.0 --port 8004 --reload
```

### Step 10: Set Up Neurohub Backend (Optional)

```bash
cd ../Neurohub

python3.11 -m venv .venv
source .venv/bin/activate

cd neurohub
pip install fastapi uvicorn pydantic sqlalchemy
uvicorn app.main:app --host 0.0.0.0 --port 8005 --reload
```

### Step 11: Run All Submodule Frontends (Optional)

Each submodule with a Flutter frontend can be run independently:

```bash
# Neurochip frontend
cd Neurochip/frontend && flutter pub get && flutter run -d macos

# Neurobench frontend
cd Neurobench/frontend && flutter pub get && flutter run -d macos

# Neurosense frontend
cd Neurosense/frontend && flutter pub get && flutter run -d macos

# Neurohub frontend
cd Neurohub/frontend && flutter pub get && flutter run -d macos
```

### Port Assignment Reference

| App | Backend Port | Frontend Dev Port |
|-----|-------------|-------------------|
| neurocnl | 8000 | 3000 |
| Neurosim | 8001 | 3001 |
| Neurochip | 8002 | 3002 |
| Neurobench | 8003 | 3003 |
| Neurosense | 8004 | 3004 |
| Neurohub | 8005 | 3005 |

---

### Quick Smoke Test

After setup, verify the core pipeline works:

```bash
# 1. neurocnl CLI pipeline
cd Neurocnl
neurocnl examples/slip_reflex.cnl --format table

# 2. neurocnl API
curl http://localhost:8000/health
curl -X POST http://localhost:8000/api/parse \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"}'

# 3. Neuro-Dream-Hand simulation (if MuJoCo installed)
cd ../Neuro-Dream-Hand
python scripts/step1_hello_physics.py

# 4. Desktop app
cd ../neuro_toolkit
flutter run -d macos
```

---

## What's Needed to Close the POC Gap

### The Single Biggest Gap

The **neuro_toolkit launcher cannot actually start or communicate with submodule backends**. It currently simulates installation with a timer. To close this gap:

1. **Process Manager:** Replace mock install with real `Process.run()` that:
   - Creates a Python venv for each module
   - Installs the module's requirements
   - Starts the FastAPI backend on the assigned port
   - Monitors the process health

2. **WebView Integration:** When a user clicks "Launch" on an installed module:
   - Open a `webview_flutter` panel pointing to `http://localhost:<port>`
   - Or embed the module's Flutter frontend directly

3. **Health Monitoring:** Poll each module's `/health` endpoint to show status in the dashboard.

### Estimated Effort to POC

| Task | Effort | Impact |
|------|--------|--------|
| Process manager in neuro_toolkit | 3-5 days | Enables real module installation |
| WebView integration for module UIs | 2-3 days | Enables launching modules |
| Neurosim minimal frontend (WebView to /docs) | 1 day | Shows the visual designer concept |
| Fix neuro_toolkit test file | 1 hour | CI passes |
| Add all 7 modules to catalog | 2 hours | Complete module listing |
| Test installer scripts (nmtk) | 1-2 days | Enables distribution |
| **Total** | **~2 weeks** | **Working POC** |

---

## Infrastructure Status

| Item | Status |
|------|--------|
| Git repository | Clean, on `dev` branch |
| CI/CD (root) | None — only in submodules (neurocnl, Neuro-Dream-Hand) |
| Docker | Dockerfiles in 5 submodules, no root compose |
| Shared UI package | nmtk_ui_core works, used by neuro_toolkit |
| Coding style guide | CODING_STYLE_GUIDE.md exists, comprehensive |
| Desktop installers | Scripts exist in nmtk/installer/ (untested) |
| Pre-commit hooks | None configured |
| Dependency management | Mix of pyproject.toml and requirements.txt |
