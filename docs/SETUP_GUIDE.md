# NeuroMorphicToolKit — Complete Setup & Installation Guide

**Last updated:** 2026-03-26
**Covers:** Docker setup, manual setup, Web frontend build, developer workflow

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Clone the Repository](#2-clone-the-repository)
3. [Option A: Docker Setup (Recommended)](#3-option-a-docker-setup-recommended)
4. [Option B: Manual Setup (Development)](#4-option-b-manual-setup-development)
5. [Running the Flutter Desktop Launcher](#5-running-the-flutter-desktop-launcher)
6. [Running Individual Modules](#6-running-individual-modules)
7. [Running the Demo Walkthrough](#7-running-the-demo-walkthrough)
8. [Port Reference](#8-port-reference)
9. [Testing](#9-testing)
10. [Developer Workflow](#10-developer-workflow)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

### Required for all setups

| Tool | Version | Check Command |
|------|---------|--------------|
| **Git** | 2.30+ | `git --version` |

> [!TIP]
> **Linux (Ubuntu/OrbStack) Users:** See the specialized [LINUX_SETUP.md](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/LINUX_SETUP.md) for Ubuntu-specific instructions and dependencies.

### For Docker setup (Option A)

| Tool | Version | Check Command |
|------|---------|--------------|
| **Docker** | 24.0+ | `docker --version` |
| **Docker Compose** | v2.20+ | `docker compose version` |

### For manual setup (Option B)

| Tool | Version | Check Command |
|------|---------|--------------|
| **Python** | 3.11+ | `python3 --version` |
| **pip** | 23.0+ | `pip --version` |
| **Poetry** | 1.7+ | `poetry --version` (needed for Neurochip and Neurobench) |

### For the Flutter desktop launcher

| Tool | Version | Check Command |
|------|---------|--------------|
| **Flutter SDK** | 3.41+ | `flutter --version` |
| **macOS desktop** | Enabled | `flutter doctor` (check macOS row) |

Enable macOS desktop development if not already:
```bash
flutter config --enable-macos-desktop
```

---

## 2. Clone the Repository

```bash
git clone --recurse-submodules https://github.com/Completed-Spoon-6/NeuroMorphicToolKit.git
cd NeuroMorphicToolKit
git checkout dev
```

If you already cloned without `--recurse-submodules`:
```bash
git submodule update --init --recursive
```

Verify all 6 checked-out submodules are present:
```bash
git submodule status
```

You should see entries for: `Neuro-Dream-Hand`, `Neurobench`, `Neurochip`, `Neurohub`, `Neurosense`, `neurocnl`.

---

## 3. Option A: Docker Setup (Recommended)

This is the fastest way to get the backend running.

### 3a. Start suite_api

```bash
docker compose up --build
```

This starts the unified `suite_api` backend on `http://localhost:9000`.

### 3b. Start with physics or hardware workers

If you need specialized hardware or physics support, you can start the corresponding workers via Docker profiles:

```bash
# Start suite_api + physics worker (MuJoCo)
docker compose --profile physics up --build

# Start suite_api + hardware workers (Neurochip/Neurosense)
docker compose --profile hardware up --build
```

### 3c. Verify service is healthy

```bash
curl http://localhost:9000/api/suite/health

# Or run the validation script
bash scripts/validate_docker_compose.sh

# Run the smoke test
bash scripts/demo_smoke_test.sh
```

### 3d. Stop services

```bash
docker compose down

# To also remove volumes:
docker compose down -v
```

---

## 4. Option B: Manual Setup (Development)

Use this when you need to develop and debug the backend with hot-reloading. Since all backend modules are now consolidated under the `suite_api` monolith, you only need to run a single server.

### 4a. Install dependencies

```bash
# Create a shared virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install core libraries in editable mode
cd neurocnl
pip install -e ".[dev]"
cd ..

cd Neuro-Dream-Hand
pip install -e ".[dev]"
cd ..

# Install suite_api
cd suite_api
pip install -e .
cd ..
```

*Note: For full hardware and benchmarking features, also install Neurochip and Neurobench using Poetry in their respective directories.*

### 4b. Start suite_api

```bash
# Note: run from the repository root so sibling module imports work
uvicorn suite_api.main:app --reload --port 9000
```

### 4c. Verify the backend

```bash
curl http://localhost:9000/api/suite/health
```

The response should return a JSON indicating `"status": "ok"` and listing the connected domains.

---

## 5. Running the Flutter Desktop Launcher

The launcher (`neuro_toolkit`) is the unified desktop app that orchestrates all modules.

### 5a. Install Flutter dependencies

```bash
# Install shared UI package
cd nmtk_ui_core
flutter pub get
cd ..

# Install launcher dependencies
cd nmtk/neuro_toolkit
flutter pub get
```

### 5b. Run the launcher

```bash
cd nmtk/neuro_toolkit
flutter run -d macos
```

For a first iPhone or iPad build, open `nmtk/neuro_toolkit/ios/Runner.xcworkspace` in Xcode once and select your local Apple Development team if Xcode prompts for signing. Do not commit that machine-local signing selection back into the repo.

### 5c. Using the launcher

1. **Dashboard** — Shows status of installed modules
2. **Catalog** — Browse all 6 available modules:
   - neurocnl / NeuroStudio (CNL Studio + Visual SNN Designer)
   - Neurochip (Hardware Deployment)
   - Neurobench (Benchmarking)
   - Neurosense (Biosignal Acquisition)
   - Neurohub (Suite Orchestrator)
   - Neuro-Dream-Hand (Prosthetic Simulator — CLI only)
3. **Install** — Click Install on a module. The launcher will:
   - Create a Python virtual environment
   - Run `pip install .` for the module
   - Mark the module as installed
4. **Launch** — Click Launch on an installed module. The launcher will:
   - Start `uvicorn` as a subprocess on the configured port
   - Poll the health endpoint until the service is ready
   - Open the module UI in an embedded WebView
   - If the venv is missing, auto-reinstall before starting
5. **Stop** — Click Stop to terminate the backend subprocess

### 5d. Building a Self-Contained macOS App (DMG)

For end-user distribution, you can build a standalone `.app` that bundles Python and all module source code. No Python pre-installation required by the end user.

```bash
# Build the standalone .app
cd nmtk/installer/macos
./build-standalone.sh

# Or build and create a DMG:
./build-standalone.sh --dmg

# Skip Flutter rebuild (if you already built):
./build-standalone.sh --skip-flutter
```

**What it does:**
1. Downloads a standalone Python 3.12 interpreter (python-build-standalone)
2. Builds the Flutter macOS app (`flutter build macos --release`)
3. Bundles Python into `.app/Contents/Frameworks/python/`
4. Copies all 6 checked-out module source dirs into `.app/Contents/Resources/modules/`
5. Code signs and optionally creates a DMG

**End-user flow:**
1. Open the DMG, drag `.app` to Applications
2. Launch the app — modules are extracted to `~/Library/Application Support/` on first run
3. Click Install on a module — venv created with bundled Python
4. Click Launch — backend starts, WebView shows the UI

**Python detection (when not bundled):**
The launcher searches for Python in this order:
1. Bundled Python inside the `.app`
2. `python3` / `python` on PATH
3. User's login shell PATH (via `zsh -lc 'which python3'`)
4. Known paths: `/opt/homebrew/bin/`, `~/anaconda3/bin/`, `~/.pyenv/shims/`, etc.

If no Python is found, a setup screen is shown with install instructions and a Homebrew install button.

### 5e. Running with custom API URL

```bash
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

---

## 6. Building and Running Module Frontends

Each module with a Flutter frontend can be run standalone (useful for development) or built as a web application and served by the corresponding backend.

### 6a. Building Flutter Web Frontends

To serve the frontend from the backend's `/` route, you must build the Flutter web app first.

```bash
# Example: Building neurocnl web frontend
cd neurocnl/frontend
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=http://localhost:9000

# After building, the suite_api backend will serve it at http://localhost:9000/neurocnl/
```

Repeat for other modules, keeping `API_BASE_URL` pointed to `suite_api` on port `9000`:
- **Neurochip:** `cd Neurochip/frontend && flutter build web --release --dart-define=API_BASE_URL=http://localhost:9000`
- **Neurobench:** `cd Neurobench/frontend && flutter build web --release --dart-define=API_BASE_URL=http://localhost:9000`
- **Neurosense:** `cd Neurosense/frontend && flutter build web --release --dart-define=API_BASE_URL=http://localhost:9000`
- **Neurohub:** `cd Neurohub/frontend && flutter build web --release --dart-define=API_BASE_URL=http://localhost:9000`

### 6b. Running Standalone Desktop Frontends (Development)

### neurocnl frontend (most complete)

```bash
cd neurocnl/frontend
flutter pub get
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:9000
```

### Neurochip frontend

```bash
cd Neurochip/frontend
flutter pub get
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:9000
```

### Neurosense frontend

```bash
cd Neurosense/frontend
flutter pub get
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:9000
```

### Neurohub frontend

```bash
cd Neurohub/frontend
flutter pub get
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:9000
```

### Neurobench frontend

```bash
cd Neurobench/frontend
flutter pub get
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:9000
```

> **Note:** Ensure `suite_api` backend is running before launching a frontend. The frontend will attempt to connect to it at the specified API_BASE_URL.

---

## 7. Running the Demo Walkthrough

The full demo flow demonstrates the core POC capability.

### Prerequisites
- Either Docker services running (Option A) or at least neurocnl backend running manually (Option B)
- Flutter desktop launcher built

### Quick demo (API only, no UI)

```bash
# Start neurocnl backend
cd neurocnl && pip install -e . && cd backend
uvicorn app.main:app --port 8000 &

# Run smoke test
bash scripts/demo_smoke_test.sh
```

### Full demo (with launcher UI)

1. Start backends (Docker recommended):
   ```bash
   docker compose up --build -d
   ```

2. Launch the desktop app:
   ```bash
   cd nmtk/neuro_toolkit
   flutter run -d macos
   ```

3. Follow the demo flow:
   - Open Catalog → Install `CNL Studio` → Launch
   - Paste a valid CNL specification
   - Confirm validation passes
   - Click `Run Simulation`
   - Click `Open in NeuroSim`
   - Confirm NeuroSim opens with the canvas already populated from the imported CNL
   - Use `Export` only if you want to save a file; export is not required for the NeuroSim handoff

### Example CNL specification

```
define neuron_group input_layer:
    type: sensory
    count: 10
    encoding: rate

define neuron_group output_layer:
    type: motor
    count: 5

define connection input_to_output:
    from: input_layer
    to: output_layer
    weight: 0.5
    learning_rule: pes
```

See `DEMO_WALKTHROUGH.md` for the full step-by-step guide with troubleshooting.

---

## 8. Port Reference

| Service | Port | Profile | Health Endpoint |
|---------|------|---------|----------------|
| suite_api | 9000 | default | `/api/suite/health` |
| neurocnl-physics-worker | 8006 | physics | `/health` |
| neurochip-hw-worker | 8002 | hardware | `/health` |
| neurosense-hw-worker | 8004 | hardware | `/health` |
| neurobench-runner-worker | 8003 | jobs | `/health` |

---

## 9. Testing

### Run all Python tests for a module

```bash
# neurocnl (most comprehensive — ~484 tests)
cd neurocnl
pytest -v

# Neuro-Dream-Hand (130+ tests)
cd Neuro-Dream-Hand
pytest -v

# NeuroStudio backend and merged canvas tests
cd neurocnl
pytest backend/tests neurosim/tests -v

# Neurochip (92% coverage)
cd Neurochip/neurochip
poetry run pytest -v

# Neurobench (98% coverage)
cd Neurobench/neurobench
poetry run pytest -v

# Neurosense
cd Neurosense/neurosense
pytest -v

# Neurohub
cd Neurohub/neurohub
pytest -v
```

### Run Flutter/Dart tests

```bash
# neuro_toolkit launcher
cd nmtk/neuro_toolkit
flutter test

# nmtk_ui_core shared package
cd nmtk_ui_core
flutter test

# neurocnl frontend
cd neurocnl/frontend
flutter test

# NeuroStudio frontend
# Canvas routes now live inside the shared neurocnl frontend.
cd neurocnl/frontend
flutter test
```

### Linting and type checking

```bash
# Python (per module)
cd <module>
ruff check .
mypy . --strict

# Dart/Flutter (per frontend)
cd <module>/frontend
flutter analyze
```

---

## 10. Developer Workflow

To ensure consistency and quality across the suite, developers should follow these practices.

### 10a. Conventional Commits

We use [Conventional Commits](https://www.conventionalcommits.org/) for all repositories. This enables automated changelog generation and version bumping.

**Format:** `<type>(<scope>): <description>`

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code (white-space, formatting, etc)
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `perf`: A code change that improves performance
- `test`: Adding missing tests or correcting existing tests
- `build`: Changes that affect the build system or external dependencies
- `ci`: Changes to CI configuration files and scripts
- `chore`: Other changes that don't modify src or test files

**Example:**
`feat(neurocnl): add support for axonal delay in simulation`

### 10b. Submodule Management

This is a monorepo that manages 6 git submodules.

**Checking out changes:**
Always use `git submodule update --init --recursive` after pulling the root repository to ensure your local submodules match the tracked commits.

**Making changes within a submodule:**
1. `cd <submodule_directory>`
2. Create a branch and make your changes.
3. Commit and push inside the submodule.
4. `cd ..` (back to root)
5. `git add <submodule_directory>` to update the pointer in the root repo.
6. Commit the pointer update in the root repo.

### 10c. Local Linting and Testing

Before submitting a PR, ensure all tests pass and the code is linted correctly.

**Python:**
```bash
ruff check .
ruff format .
mypy . --strict
pytest
```

**Flutter/Dart:**
```bash
flutter analyze
flutter test
```

### 10d. Pre-commit Hooks

We recommend installing [pre-commit](https://pre-commit.com/) to automate these checks.

```bash
pip install pre-commit
pre-commit install
```

---

## 11. Troubleshooting

### Docker issues

**Port already in use:**
```bash
# Find what's using the port
lsof -i :8000
# Kill the process or change the port in .env
```

**Build fails with COPY error:**
```bash
# Rebuild without cache
docker compose build --no-cache <service-name>
```

**Healthcheck failing:**
```bash
# Check container logs
docker compose logs <service-name>

# Enter container for debugging
docker compose exec <service-name> bash
```

### Flutter issues

**`flutter pub get` fails in neuro_toolkit:**
```bash
# Ensure nmtk_ui_core is accessible
cd nmtk_ui_core && flutter pub get
cd ../nmtk/neuro_toolkit && flutter pub get
```

**WebView not loading:**
- Verify the backend is running: `curl http://localhost:<port>/health`
- Check if macOS network permissions are granted
- Fallback: click "Open in Browser" to use system browser instead

**macOS build fails:**
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run -d macos
```

### Python backend issues

**Module import errors:**
```bash
# Ensure core libraries are installed first
cd neurocnl && pip install -e .
cd ../Neuro-Dream-Hand && pip install -e .
```

**Poetry not found (Neurochip/Neurobench):**
```bash
# Install Poetry
curl -sSL https://install.python-poetry.org | python3 -
```

**uvicorn not found:**
```bash
pip install uvicorn[standard]
```

**Headless MuJoCo rendering issues:**
If you are running on a headless server (e.g., CI or a Linux server without a display), set `MUJOCO_GL=egl` before starting the simulation:
```bash
export MUJOCO_GL=egl
```

### Submodule issues

**Submodules are empty:**
```bash
git submodule update --init --recursive
```

**Submodule on wrong branch:**
```bash
cd <submodule>
git checkout dev
git pull origin dev
```

**Detached HEAD in submodule:**
```bash
cd <submodule>
git checkout dev
```

---

## Architecture Reference

```
NeuroMorphicToolKit/
├── suite_api/             # Unified monolithic backend (port 9000)
├── neurocnl/              # Core CNL compiler, NeuroStudio canvas, and frontend (submodule)
│   └── frontend/          # Shared Flutter frontend (served by suite_api)
├── Neuro-Dream-Hand/      # Prosthetic SNN simulator (submodule)
├── Neurochip/             # Hardware deployment toolkit (submodule)
│   └── frontend/          # Flutter frontend (served by suite_api)
├── Neurobench/            # Benchmarking workbench (submodule)
│   └── frontend/          # Flutter frontend (served by suite_api)
├── Neurosense/            # Biosignal acquisition (submodule)
│   └── frontend/          # Flutter frontend (served by suite_api)
├── Neurohub/              # Suite orchestrator (submodule)
│   └── frontend/          # Flutter frontend (served by suite_api)
├── nmtk/                  # Installer, CI, and launcher
│   ├── neuro_toolkit/     # Flutter desktop launcher
│   ├── scripts/           # Setup scripts
│   └── installer/         # Platform installers (macOS, Linux, Windows)
├── nmtk_ui_core/          # Shared Flutter design system
├── docker-compose.yml     # Root orchestration (suite_api + workers)
├── scripts/               # Demo and validation scripts
├── DEMO_WALKTHROUGH.md    # Step-by-step demo guide
└── SETUP_GUIDE.md         # This file
```
