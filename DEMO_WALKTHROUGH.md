# NeuroMorphicToolkit (NMTK) — POC Demo Walkthrough

This document provides a step-by-step guide to demonstrating the full POC scenario for the NeuroMorphicToolkit.

---

## 1. Environment Setup

### 1.1 Start the Backends

**Option A — Root docker-compose (recommended):**
```bash
# Start core services (neurocnl, neurosim, neurochip)
docker compose up -d

# Or start all services including neurobench, neurosense, neurohub
docker compose --profile full up -d
```

**Option B — Individual module containers:**
```bash
cd neurocnl && docker compose up -d
cd Neurosim && docker compose up -d
cd Neurochip && docker compose up -d
```

**Expected output:**
```
[+] Running 4/4
 ✔ Network nmtk-network  Created
 ✔ Container neuromorphictoolkit-neurocnl-1   Healthy
 ✔ Container neuromorphictoolkit-neurosim-1    Healthy
 ✔ Container neuromorphictoolkit-neurochip-1   Healthy
```

Verify services are healthy:
```bash
curl -s http://localhost:8000/health   # neurocnl  → {"status":"ok"}
curl -s http://localhost:8001/health   # neurosim  → {"status":"ok"}
curl -s http://localhost:8002/health   # neurochip → {"status":"ok"}
```

### 1.2 Open the Launcher
Open the NMTK Desktop Launcher (Flutter app).
```bash
cd nmtk/neuro_toolkit/
flutter run -d macos  # or linux, windows
```

**Expected output:**
```
Launching lib/main.dart on macOS in debug mode...
Building macOS application...
Syncing files to device macOS...
```

---

## 2. Guided Walkthrough

### 2.1 Browse the Module Catalog
Upon opening the launcher, you should see the **Module Catalog** showing all 7 available modules.

*   **NeuroCNL:** Controlled Natural Language compiler.
*   **Neurosim:** Simulation environment.
*   **Neurosense:** Sensory encoding.
*   **Neurochip:** Hardware interfacing.
*   **Neurobench:** Benchmarking.
*   **Neurohub:** Model repository.
*   **Neuro-Dream-Hand:** Robotics integration.

> **[PLACEHOLDER: Screenshot of Module Catalog showing 7 modules]**
>
> *You should see a grid/list of 7 module cards, each showing the module name, a brief description, and an Install/Launch button.*

### 2.2 Install a Module
1.  Locate **NeuroCNL** in the catalog.
2.  Click the **Install** button.
3.  Observe the real-time installation progress as the application creates a virtual environment and installs dependencies.

> **[PLACEHOLDER: Screenshot of NeuroCNL installation in progress]**
>
> *A progress indicator shows dependency installation. Once complete, the button changes from "Install" to "Launch".*

**Expected behavior:** Installation takes 30-60 seconds depending on your system. The progress bar updates in real time.

### 2.3 Launch NeuroCNL Studio
1.  Once installed, the button will change to **Launch**.
2.  Click **Launch** to open the NeuroCNL Studio interface (embedded WebView).

> **[PLACEHOLDER: Screenshot of NeuroCNL Studio opening]**
>
> *The NeuroCNL Studio opens in an embedded WebView tab within the launcher, showing an editor panel and a results panel.*

### 2.4 Write a CNL Specification
In the editor, type a simple reflex arc specification. You can use the following example:

```text
# Simple Reflex Arc
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5
The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.7
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 2.0
```

### 2.5 Validate the Specification
Click the **Validate** button. The system will check the specification against Layer 1 (biophysical invariants) and Layer 2 (structural consistency).

*   Verify that the validation results appear, showing passed/failed invariants.

> **[PLACEHOLDER: Screenshot of Validation results showing green/red indicators]**
>
> *The results panel shows a checklist of invariants. Green checkmarks indicate passed checks (e.g., threshold within biophysical range, valid synaptic weight).*

**Expected API response:**
```json
{
  "overall": true,
  "layer1": {"passed": true, "checks": [...]},
  "layer2": {"passed": true, "checks": [...]}
}
```

### 2.6 Run a Simulation
1.  Click the **Simulate** button.
2.  Once the simulation completes, view the **Spike Raster Plot** and membrane potential graphs.

> **[PLACEHOLDER: Screenshot of Spike Raster Plot showing sensory and motor spikes]**
>
> *A spike raster plot displays time on the x-axis and neuron index on the y-axis, with dots marking spike events. A membrane potential trace shows the voltage over time for each neuron.*

**Expected behavior:** Simulation submits a job (you may see a spinner), then renders results within a few seconds.

### 2.7 Export to Hardware
1.  Click the **Export** button.
2.  Select the **C Header** or **Crossbar HDF5** format.
3.  The file is generated and downloaded, ready for deployment to hardware (e.g., Teensy 4.1 or Loihi).

---

## 3. Exploring Other Modules

### 3.1 Neurosim Canvas
1.  Return to the Launcher and launch **Neurosim**.
2.  Observe the visual canvas where populations of neurons can be placed and connected.

> **[PLACEHOLDER: Screenshot of Neurosim Canvas with placed neuron populations]**
>
> *The canvas shows draggable neuron population nodes connected by edges representing synaptic connections.*

### 3.2 Neurochip Analysis
1.  Launch **Neurochip**.
2.  Show the **Constraint Analysis** for target hardware like **Teensy 4.1**, highlighting memory and compute limits.

> **[PLACEHOLDER: Screenshot of Neurochip hardware constraint analysis]**
>
> *A dashboard showing hardware constraints: memory usage bar, compute budget, supported neuron count, and compatibility status.*

---

## 4. Programmatic Verification (Smoke Test)

For developers, a smoke test script is available to verify the API functionality programmatically.

```bash
./scripts/demo_smoke_test.sh
```

This script validates that the backends are healthy and can handle parse, validate, and simulate requests.

**Example successful output:**
```
🚀 Starting NMTK POC Smoke Test...
📍 Using API Base URL: http://localhost:8000
🚀 Starting neurocnl backend...
⏳ Waiting for backend health check...
✅ Backend is healthy!
🔍 Testing /api/parse...
✅ Parse successful!
⚖️ Testing /api/validate...
✅ Validation successful!
⚡ Testing /api/simulate...
✅ Simulation job submitted (ID: abc123-...)
⏳ Waiting for simulation results...
✅ Simulation completed successfully!
🎉 All POC Smoke Tests Passed!
```

**Example failure output:**
```
❌ Timeout waiting for backend health check.
```
This typically means the backend failed to start. Check `/tmp/nmtk_smoke_test_backend.log` for details.

---

## 5. Troubleshooting

### Port already in use
```
Error: address already in use :::8000
```
**Fix:** Kill the existing process or change the port in `.env`:
```bash
lsof -ti:8000 | xargs kill -9   # kill process on port 8000
# Or edit .env to use different ports
```

### Docker containers fail to start
```bash
# Check container logs
docker compose logs neurocnl

# Rebuild from scratch
docker compose down && docker compose build --no-cache && docker compose up -d
```

### Health checks failing
Services take up to 50 seconds to become healthy (10s interval x 5 retries). Wait and check again:
```bash
docker compose ps   # shows health status for each service
```

### Flutter app won't launch
```bash
# Ensure Flutter is installed and up to date
flutter doctor

# Clean and rebuild
cd nmtk/neuro_toolkit && flutter clean && flutter pub get && flutter run -d macos
```

### Smoke test fails with "python3 not found"
Ensure Python 3.10+ is on your PATH and uvicorn is installed:
```bash
python3 --version
pip3 install uvicorn fastapi
```

### Module installation hangs
Check that the backend for the module is actually running. The installer needs the backend API to be accessible:
```bash
curl -s http://localhost:8000/health
```
