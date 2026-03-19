# NeuroMorphicToolKit — POC Setup & Implementation Guide

**Generated:** 19 March 2026
**Author:** Claude Opus 4.6
**Purpose:** Step-by-step guide to get from current state to a running POC

---

## What the POC Should Demonstrate

**The minimum viable demo flow:**

```
User opens neuro_toolkit desktop app
  → Browses module catalog (7 modules listed)
  → Installs "neurocnl" (backend starts via Docker/venv)
  → Launches neurocnl
  → WebView opens showing the CNL Studio
  → User writes: "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"
  → Clicks Validate → Parse → Generate → Simulate
  → Sees spike raster plot and simulation results
  → Exports to NeuroML or C header format
```

**The extended demo (adds wow factor):**
- Also install Neurosim → show the visual SNN designer canvas
- Also install Neurochip → show hardware constraint analysis for Teensy 4.1
- Run a Neuro-Dream-Hand simulation → show prosthetic hand physics

---

## Part 1: What You Can Run RIGHT NOW (Zero Code Changes)

### 1A. neurocnl — Full Pipeline via Docker

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl

# Start both backend and frontend
docker-compose up --build

# Backend API: http://localhost:8000/docs
# Frontend:   http://localhost:8080
```

**Test the API manually:**

```bash
# Health check
curl http://localhost:8000/health

# Parse a CNL spec
curl -X POST http://localhost:8000/api/parse \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"}'

# Validate
curl -X POST http://localhost:8000/api/validate \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"}'

# Generate Nengo code
curl -X POST http://localhost:8000/api/generate \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"}'
```

### 1B. neurocnl — Full Pipeline via CLI

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl

# Create venv and install
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"

# Run the CLI on an example spec
neurocnl examples/slip_reflex.cnl --format table

# Run all tests
pytest tests/ -v
```

### 1C. Neuro-Dream-Hand — Physics Simulation

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neuro-Dream-Hand

# Conda recommended for MuJoCo
conda create -n nengo-mujoco python=3.11 -y
conda activate nengo-mujoco
pip install -e ".[physics,dev]"

# Run tutorial scripts
python scripts/step1_hello_physics.py
python scripts/step3_reflex.py

# Run tests
pytest tests/ -v
```

### 1D. Neurosim — Backend API Only

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosim

docker-compose up --build
# API docs at http://localhost:8001/docs
```

Or without Docker:

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosim
python3.11 -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn pydantic
cd neurosim
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

### 1E. Neurochip — Backend API Only

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip

docker-compose up --build
# API docs at http://localhost:8002/docs
```

### 1F. neuro_toolkit — Launcher Shell (Mock Only)

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit/neuro_toolkit
flutter pub get
flutter run -d macos
```

This shows the UI but all installation/launching is fake.

---

## Part 2: What Needs to Be Built for a Real POC

### Gap 1: neuro_toolkit Process Orchestration (CRITICAL)

**Current state:** `ModuleProvider` in `neuro_toolkit/lib/providers/module_provider.dart` uses `Future.delayed()` to simulate installation. There is no real process management.

**What needs to happen:**

#### Option A: Docker-based (Recommended for POC)

Replace the mock install logic with real Docker orchestration:

```
ModuleProvider.install(module) should:
  1. Check if Docker is running (docker info)
  2. Navigate to the module's directory
  3. Run `docker-compose up -d` via Process.run()
  4. Poll the module's /health endpoint until it responds
  5. Update state to "installed + running"

ModuleProvider.launch(module) should:
  1. If not running, start Docker container
  2. Open a WebView pointing to http://localhost:<port>

ModuleProvider.uninstall(module) should:
  1. Run `docker-compose down` via Process.run()
  2. Optionally remove the Docker image
  3. Update state
```

**Key files to modify:**
- `neuro_toolkit/lib/providers/module_provider.dart` — replace mock logic
- `neuro_toolkit/lib/screens/tool_view_screen.dart` — replace mock terminal with WebView
- `neuro_toolkit/pubspec.yaml` — add `webview_flutter` dependency

**Module registry needed (hardcoded is fine for POC):**

```dart
const moduleRegistry = {
  'neurocnl': ModuleConfig(
    name: 'neurocnl',
    displayName: 'NeuroCNL — CNL Compiler & SNN Engine',
    directory: '../neurocnl',
    backendPort: 8000,
    frontendPort: 8080,
    healthEndpoint: '/health',
    hasDocker: true,
  ),
  'neurosim': ModuleConfig(
    name: 'neurosim',
    displayName: 'NeuroSim — Visual SNN Designer',
    directory: '../Neurosim',
    backendPort: 8001,
    healthEndpoint: '/health',
    hasDocker: true,
  ),
  'neurochip': ModuleConfig(
    name: 'neurochip',
    displayName: 'NeuroChip — Hardware Deployment',
    directory: '../Neurochip',
    backendPort: 8002,
    healthEndpoint: '/health',
    hasDocker: true,
  ),
  'neurosense': ModuleConfig(
    name: 'neurosense',
    displayName: 'NeuroSense — Biosignal Acquisition',
    directory: '../Neurosense',
    backendPort: 8004,
    healthEndpoint: '/health',
    hasDocker: true,
  ),
  'neurohub': ModuleConfig(
    name: 'neurohub',
    displayName: 'NeuroHub — Suite Dashboard',
    directory: '../Neurohub',
    backendPort: 8005,
    healthEndpoint: '/health',
    hasDocker: false, // No Dockerfile yet
  ),
  'neurobench': ModuleConfig(
    name: 'neurobench',
    displayName: 'NeuroBench — Benchmarking',
    directory: '../Neurobench',
    backendPort: 8003,
    healthEndpoint: '/health',
    hasDocker: false, // docker-compose.yml is blank
  ),
  'neurodreamhand': ModuleConfig(
    name: 'neurodreamhand',
    displayName: 'Neuro-Dream-Hand — Prosthetic Simulator',
    directory: '../Neuro-Dream-Hand',
    backendPort: null, // No web service
    healthEndpoint: null,
    hasDocker: false,
  ),
};
```

#### Option B: venv-based (Simpler, no Docker dependency)

Instead of Docker, use Python venvs directly:

```
install:
  1. python3.11 -m venv <module_dir>/.venv
  2. .venv/bin/pip install -r requirements.txt
  3. Store venv path in app state

launch:
  1. Process.start('.venv/bin/uvicorn', ['app.main:app', '--port', '<port>'])
  2. Store PID for cleanup
  3. Open WebView to localhost:<port>

uninstall:
  1. Kill stored PID
  2. rm -rf .venv
```

This is simpler but less isolated. For POC, either works.

---

### Gap 2: WebView Integration (CRITICAL)

**Current state:** `ToolViewScreen` shows a mock terminal with fake output.

**What needs to happen:** When a module is launched, open its web UI in an embedded browser.

**Flutter packages to consider:**
- `webview_flutter` — official Flutter WebView (iOS/Android/web)
- `webview_windows` — Windows desktop WebView2
- `desktop_webview_window` — cross-platform desktop WebView
- For macOS specifically, `macos_webview` or `flutter_inappwebview`

**Simplest approach for macOS POC:**

```dart
// In tool_view_screen.dart, replace the mock terminal with:
import 'dart:io';

// Option 1: Open in system browser (zero dependencies)
Process.run('open', ['http://localhost:${module.backendPort}/docs']);

// Option 2: Use url_launcher package
import 'package:url_launcher/url_launcher.dart';
launchUrl(Uri.parse('http://localhost:${module.backendPort}'));
```

For an embedded experience, `flutter_inappwebview` supports macOS and can render the module's frontend inside a tab.

---

### Gap 3: Root Docker Orchestration (HIGH)

**Current state:** No root `docker-compose.yml`. Each module is isolated.

**What to create:** A root compose file that brings up all working backends:

```yaml
# /Users/yoshimartodihardjo/NeuroMorphicToolKit/docker-compose.yml
version: '3.8'

services:
  neurocnl-backend:
    build:
      context: ./neurocnl/backend
    ports:
      - "8000:8000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  neurocnl-frontend:
    build:
      context: ./neurocnl/frontend
    ports:
      - "8080:8080"
    depends_on:
      neurocnl-backend:
        condition: service_healthy

  neurosim:
    build:
      context: ./Neurosim
    ports:
      - "8001:8000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s

  neurochip:
    build:
      context: ./Neurochip
    ports:
      - "8002:8000"

  neurosense:
    build:
      context: ./Neurosense
    ports:
      - "8004:8000"
```

**One-command startup:** `docker-compose up --build`

This gets 4 backends + 1 frontend running simultaneously.

---

### Gap 4: Neurosim Frontend (HIGH — Hardest Task)

**Current state:** 14 Dart files, all boilerplate. No canvas, no drag-and-drop, no visualization.

**Minimum viable approach for POC:**

**Option A: WebView to Swagger docs (1 hour)**
- When Neurosim is launched, just open `http://localhost:8001/docs` in a browser
- Shows all 13 endpoints are functional
- Not impressive but proves the backend works

**Option B: Minimal Flutter canvas (3-5 days)**
- Implement NS-D1: basic canvas with draggable neuron population nodes
- Wire to `/api/neurosim/components` for the component palette
- Wire to `/api/neurosim/preview` for simulation preview
- Skip parameter sweeps, export, and project management for POC

**Option C: React/HTML canvas served by backend (2-3 days)**
- Build a simple HTML/JS canvas UI
- Serve it as static files from the FastAPI backend
- Users access it at `http://localhost:8001/`
- Faster to build than Flutter canvas, can be replaced later

---

### Gap 5: Fix Neurobench Docker (MEDIUM)

```bash
# Neurobench/docker-compose.yml is currently BLANK
# Needs to be populated:
```

```yaml
version: '3.8'
services:
  neurobench:
    build:
      context: .
    ports:
      - "8003:8000"
    volumes:
      - ./data:/app/data
```

Also need to verify `Neurobench/Dockerfile` actually works.

---

### Gap 6: Add Neurohub Docker (LOW)

Neurohub has no Dockerfile at all. For POC:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY neurohub/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY neurohub/ .
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## Part 3: Recommended POC Sprint Plan

### Week 1: Make the Launcher Real

| Day | Task | Module | Deliverable |
|-----|------|--------|------------|
| 1 | Replace ModuleProvider mock with Docker subprocess calls | neuro_toolkit | Modules actually install |
| 2 | Add all 7 modules to catalog with correct metadata | neuro_toolkit | Full catalog |
| 2 | Add url_launcher or WebView for module launch | neuro_toolkit | Clicking "Launch" opens the real UI |
| 3 | Create root docker-compose.yml | nmtk | `docker-compose up` starts everything |
| 3 | Add health polling to DashboardScreen | neuro_toolkit | Green/red status indicators |
| 4 | Fix the broken test file, add 2-3 basic widget tests | neuro_toolkit | CI passes |
| 5 | End-to-end test: install neurocnl from launcher, write spec, see results | — | POC milestone 1 |

### Week 2: Add Visual Impact

| Day | Task | Module | Deliverable |
|-----|------|--------|------------|
| 6-8 | Minimal Neurosim canvas (drag populations, preview simulation) | Neurosim | Visual "wow" moment |
| 9 | Wire Neurobench CLI + fix Docker | Neurobench | `neurobench run grip-stability` works |
| 9 | Finish Neurochip QuantizationExplorer widget | Neurochip | Shows hardware analysis |
| 10 | Polish, write demo script, record walkthrough video | all | Demo-ready POC |

---

## Part 4: Quick Reference

### Port Map

| Module | Backend | Frontend | Health Check |
|--------|---------|----------|-------------|
| neurocnl | :8000 | :8080 | GET /health |
| Neurosim | :8001 | — | GET /health |
| Neurochip | :8002 | — | GET /health |
| Neurobench | :8003 | — | GET /health |
| Neurosense | :8004 | — | GET /health |
| Neurohub | :8005 | — | GET /health |

### Key File Locations

```
Launcher entry:     neuro_toolkit/lib/main.dart
Module provider:    neuro_toolkit/lib/providers/module_provider.dart
Launch screen:      neuro_toolkit/lib/screens/tool_view_screen.dart
Shared theme:       nmtk_ui_core/lib/src/app_theme.dart

neurocnl backend:   neurocnl/backend/app/main.py
neurocnl frontend:  neurocnl/frontend/lib/main.dart
neurocnl Docker:    neurocnl/docker-compose.yml

Neurosim backend:   Neurosim/neurosim/app/main.py
Neurosim Docker:    Neurosim/docker-compose.yml

Neurochip backend:  Neurochip/neurochip/app/main.py
Neurochip Docker:   Neurochip/docker-compose.yml

Neurobench backend: Neurobench/neurobench/app/main.py
Neurobench Docker:  Neurobench/docker-compose.yml  (BLANK!)

Neurosense backend: Neurosense/neurosense/app/main.py
Neurosense Docker:  Neurosense/docker-compose.yml

Neurohub backend:   Neurohub/neurohub/app/main.py
Neurohub Docker:    (MISSING)

Installers:         nmtk/installer/{macos,linux,windows}/
```

### Prerequisites

| Tool | Version | Required For |
|------|---------|-------------|
| Flutter SDK | >= 3.6.0 | neuro_toolkit, all frontends |
| Dart SDK | >= 3.6.0 | (included with Flutter) |
| Python | >= 3.11 | All backends |
| Docker + Docker Compose | Latest | Container orchestration |
| Xcode | >= 15.0 | macOS Flutter builds |
| conda | Any | Neuro-Dream-Hand (optional) |

### Smoke Test After Setup

```bash
# 1. Start all backends
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit
docker-compose up --build  # (after root compose is created)

# 2. Verify backends
curl http://localhost:8000/health  # neurocnl
curl http://localhost:8001/health  # Neurosim
curl http://localhost:8002/health  # Neurochip

# 3. Test the core pipeline
curl -X POST http://localhost:8000/api/parse \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"}'

# 4. Launch the desktop app
cd neuro_toolkit && flutter run -d macos

# 5. Run neurocnl CLI
cd neurocnl && neurocnl examples/slip_reflex.cnl --format table
```

---

## Summary: The 3 Things That Matter Most

1. **Wire the launcher to Docker** — Replace 50 lines of mock code in `module_provider.dart` with real `Process.run('docker-compose', ...)` calls. This single change unlocks the entire POC.

2. **Add WebView or url_launcher** — When "Launch" is clicked, open the module's web UI. Even just `Process.run('open', ['http://localhost:8000'])` works for macOS POC.

3. **Create a root docker-compose.yml** — One file that starts neurocnl + Neurosim + Neurochip + Neurosense. Makes setup trivial: `docker-compose up`.

Everything else is polish. These three changes turn a collection of working backends and a pretty shell into an actual integrated POC.
