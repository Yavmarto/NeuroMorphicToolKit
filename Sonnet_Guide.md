# NMTK Desktop POC — Step-by-Step Run Guide
**Platform:** macOS | **Model:** Claude Sonnet 4.6 | **Date:** 19 March 2026

This guide gets the NeuroMorphicToolKit running locally on macOS for a POC demonstration. It covers three levels of depth:

- **Level 1 — Fastest Demo:** Run `neurocnl` directly (5 minutes, no Docker needed)
- **Level 2 — Full Backend Stack:** Spin up all module backends via Docker
- **Level 3 — Desktop App:** Launch the Flutter `neuro_toolkit` app and connect it to the backends

---

## Prerequisites

### Check what you have

```bash
python3 --version      # need 3.11+
flutter --version      # need 3.x
docker --version       # need 20+
conda --version        # needed for Neuro-Dream-Hand
```

### Install anything missing

```bash
# Python 3.11 (via pyenv recommended)
brew install pyenv
pyenv install 3.11.9
pyenv global 3.11.9

# Flutter (if not installed)
brew install flutter

# Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop/
# Start Docker Desktop before proceeding.

# Conda (if not installed)
brew install miniconda
```

---

## Clone and initialise the repo

```bash
# If you haven't already — clone with submodules
git clone --recurse-submodules https://github.com/Yavmarto/NeuroMorphicToolKit.git
cd NeuroMorphicToolKit

# If you already cloned but submodules are empty
git submodule update --init --recursive
```

---

---

# Level 1 — Fastest Demo: neurocnl CLI (5 minutes)

This runs the core CNL compiler directly in your terminal. No Docker, no Flutter.

## Step 1: Install the neurocnl library

```bash
cd neurocnl
pip install -e ".[dev]"
```

## Step 2: Run the full pipeline on a built-in example

```bash
# Parse → validate → generate → simulate → report
neurocnl examples/slip_reflex.cnl

# Or try the EMG gripper spec
neurocnl examples/emg_gripper.cnl

# Formatted table output
neurocnl examples/slip_reflex.cnl --format table

# Validate only (no simulation)
neurocnl --validate-only examples/slip_reflex.cnl
```

**Expected output:** A coloured terminal report showing parsed CNL concepts, validation results, Nengo network topology, and simulation summary.

## Step 3: Run the test suite to confirm everything works

```bash
cd neurocnl
pytest tests/ -v --tb=short
# Expected: 305 passed, ~25s
```

---

---

# Level 2 — Full Backend Stack via Docker

This starts all module backends as Docker containers. Each backend is then accessible via its REST API.

## Step 1: Start Docker Desktop

Make sure the Docker Desktop app is running before proceeding.

## Step 2: Start the neurocnl backend (core engine — start this first)

```bash
cd /path/to/NeuroMorphicToolKit/neurocnl
docker-compose up --build -d
```

Wait ~60 seconds for the image to build on first run.

**Verify:**
```bash
curl http://localhost:8000/health
# Expected: {"status":"ok","version":"0.3.0"}
```

**Frontend (Flutter web, served by nginx):**
```
http://localhost:3000
```

---

## Step 3: Start the Neurosim backend (visual design workbench)

```bash
cd /path/to/NeuroMorphicToolKit/Neurosim
docker-compose up --build -d
```

**Verify:**
```bash
curl http://localhost:8000/api/neurosim/components
# Expected: JSON array of available neuron/synapse components
```

> **Port conflict note:** Both `neurocnl` and `Neurosim` default to `:8000`.
> Run them on different ports if you need both simultaneously:
>
> ```bash
> # Override Neurosim's port:
> API_PORT=8001 docker-compose up -d
> # or edit docker-compose.yml to change "8000:8000" → "8001:8000"
> ```

---

## Step 4: Start the Neurochip backend (hardware deployment)

```bash
cd /path/to/NeuroMorphicToolKit/Neurochip
docker-compose up --build -d
```

**Verify:**
```bash
curl http://localhost:8000/api/neurochip/targets
# Expected: JSON array of hardware profiles (Teensy 4.1, Loihi 2, etc.)
```

> Map this to port `:8002` if neurocnl is already on `:8000`:
> Edit `Neurochip/docker-compose.yml`: `"8002:8000"`

---

## Step 5: Start the Neuro-Dream-Hand simulation (physics SNN demo)

This one runs outside Docker as a conda environment.

```bash
cd /path/to/NeuroMorphicToolKit/Neuro-Dream-Hand

# First time only: create the conda environment
conda env create -f environment.yml
conda activate nengo-mujoco
pip install -e ".[physics,video]"

# Run the reflex + continual learning demo
python scripts/step3_reflex.py
```

**Expected output:** A MuJoCo simulation window opens showing the prosthetic hand gripping an object. The SNN controller adapts in real time. A terminal progress log shows force/slip metrics per timestep.

**Run other demos:**
```bash
# Sleep consolidation demo (no MuJoCo window — pure SNN training)
python scripts/step5_sleep.py

# Full OCL experiment (online continual learning sweep)
python scripts/step8_ocl_sweep.py
```

---

## Step 6: Verify the backend stack

```bash
# Check all running containers
docker ps

# Expected: neurocnl-backend, neurocnl-frontend, neurosim-backend, neurochip-backend

# Tail logs for a specific service
docker logs neurocnl-backend -f
```

---

---

# Level 3 — Flutter Desktop App (neuro_toolkit)

This launches the unified desktop launcher app. It currently shows a module catalog and can open module UIs in a WebView tab. The Docker orchestration from inside the app is a work in progress — start backends manually (Level 2) and the launcher can connect to them.

## Step 1: Install the shared UI package

```bash
cd /path/to/NeuroMorphicToolKit/nmtk_ui_core
flutter pub get
```

## Step 2: Install the main app dependencies

```bash
cd /path/to/NeuroMorphicToolKit/neuro_toolkit
flutter pub get
```

If `flutter pub get` fails with a dependency error on `nmtk_ui_core`:
```bash
# Confirm the path dep is resolved
cat pubspec.yaml | grep nmtk_ui_core
# Should show: nmtk_ui_core: path: ../nmtk_ui_core
```

## Step 3: Run the app in macOS desktop mode

```bash
cd /path/to/NeuroMorphicToolKit/neuro_toolkit
flutter run -d macos
```

**Expected:** The NMTK desktop window opens with a Dashboard tab (installed modules) and a Catalog tab (available modules to install).

> **If macOS build fails** (missing entitlements or signing):
> ```bash
> # Open in Xcode to configure signing
> open macos/Runner.xcworkspace
> # Select your Team in Signing & Capabilities → Runner target
> ```

## Step 4: Connect a module manually

Since Docker orchestration from inside the app is not yet wired:

1. Start a backend manually (see Level 2 — e.g. neurocnl on `:8000`, frontend on `:3000`).
2. In the NMTK app, click **Catalog → Install** for "NeuroCNL".
3. Click **Dashboard → Launch** for NeuroCNL.
4. The app opens a WebView pointing to `http://localhost:3000` — the neurocnl Flutter frontend.

---

## Step 5: Run the neurocnl frontend directly (alternative to WebView)

If you want to develop the neurocnl frontend natively:

```bash
cd /path/to/NeuroMorphicToolKit/neurocnl/frontend
flutter pub get
flutter run -d macos
# Or target Chrome for web:
flutter run -d chrome
```

---

---

# Troubleshooting

### `pull-all.sh` exits with code 1
**Cause:** One or more submodule repos doesn't have a `dev` branch, or has unstaged changes.

```bash
# Pull with main/master instead
./pull-all.sh main

# Or update a specific submodule manually
cd neurocnl
git checkout main && git pull origin main
```

---

### `docker-compose up` fails: port already in use

```bash
# Find what's using the port
lsof -i :8000

# Kill the offending process
kill -9 <PID>

# Or change the host port in docker-compose.yml:
# "8001:8000"  ← external:internal
```

---

### `flutter pub get` fails: `nmtk_ui_core` not found

```bash
# Make sure nmtk_ui_core is present
ls /path/to/NeuroMorphicToolKit/nmtk_ui_core/lib/

# Re-run pub get from the root
cd neuro_toolkit && flutter pub get
```

---

### `neurocnl` CLI: `ModuleNotFoundError: nengo`

```bash
pip install nengo>=3.2.0
# Or install all dev deps:
pip install -e ".[dev]"
```

---

### MuJoCo error on Apple Silicon

```bash
# Install the arm64 MuJoCo wheel
pip install mujoco --upgrade

# If that fails:
conda install -c conda-forge mujoco
```

---

### `conda env create` hangs or is slow

```bash
# Use mamba (faster conda solver)
brew install micromamba
micromamba env create -f environment.yml
micromamba activate nengo-mujoco
```

---

---

# Module Port Reference

When running all backends simultaneously, use these ports to avoid conflicts:

| Module | Suggested host port | Service |
|---|---|---|
| neurocnl backend | 8000 | FastAPI |
| neurocnl frontend | 3000 | Flutter web (nginx) |
| Neurosim backend | 8001 | FastAPI |
| Neurochip backend | 8002 | FastAPI |
| Neurobench backend | 8003 | FastAPI (once Docker is wired) |
| Neurohub backend | 8004 | FastAPI |
| Neurosense backend | 8005 | FastAPI |

Update the `ports:` mapping in each `docker-compose.yml`:
```yaml
ports:
  - "8001:8000"   # host:container
```

---

# Minimal POC Demo Script

The fastest end-to-end demonstration of the toolkit's value:

```bash
# Terminal 1 — Start neurocnl (core engine)
cd neurocnl && docker-compose up -d

# Terminal 2 — Run the Neuro-Dream-Hand simulation
cd Neuro-Dream-Hand
conda activate nengo-mujoco
python scripts/step3_reflex.py   # watch the SNN control a prosthetic hand

# Terminal 3 — Hit the neurocnl API directly
# Parse a CNL spec:
curl -X POST http://localhost:8000/api/parse \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"}'

# Run a full pipeline job:
curl -X POST http://localhost:8000/api/jobs \
  -H "Content-Type: application/json" \
  -d '{"spec_path": "examples/slip_reflex.cnl", "backend": "nengo"}'

# Open the neurocnl web UI
open http://localhost:3000
```

This gives you:
- A physics simulation of neuromorphic prosthetic control
- A live REST API for CNL compilation
- A web UI for building SNN specs
