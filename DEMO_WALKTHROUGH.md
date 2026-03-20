# NeuroMorphicToolkit (NMTK) — POC Demo Walkthrough

This document provides a step-by-step guide to demonstrating the full POC scenario for the NeuroMorphicToolkit.

---

## 1. Environment Setup

### 1.1 Start the Backends
To start the full suite of neuromorphic backends, you can use the root `docker-compose.yml` (if available) or start individual module backends.

**Using individual commands:**
```bash
# Start NeuroCNL backend
cd neurocnl && docker compose up -d

# Start Neurosim backend
cd Neurosim && docker compose up -d

# Start Neurochip backend
cd Neurochip && docker compose up -d
```

### 1.2 Open the Launcher
Open the NMTK Desktop Launcher (Flutter app).
```bash
cd nmtk/neuro_toolkit/
flutter run -d macos  # or your target platform
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

### 2.2 Install a Module
1.  Locate **NeuroCNL** in the catalog.
2.  Click the **Install** button.
3.  Observe the real-time installation progress as the application creates a virtual environment and installs dependencies.

> **[PLACEHOLDER: Screenshot of NeuroCNL installation in progress]**

### 2.3 Launch NeuroCNL Studio
1.  Once installed, the button will change to **Launch**.
2.  Click **Launch** to open the NeuroCNL Studio interface (embedded WebView).

> **[PLACEHOLDER: Screenshot of NeuroCNL Studio opening]**

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

### 2.6 Run a Simulation
1.  Click the **Simulate** button.
2.  Once the simulation completes, view the **Spike Raster Plot** and membrane potential graphs.

> **[PLACEHOLDER: Screenshot of Spike Raster Plot showing sensory and motor spikes]**

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

### 3.2 Neurochip Analysis
1.  Launch **Neurochip**.
2.  Show the **Constraint Analysis** for target hardware like **Teensy 4.1**, highlighting memory and compute limits.

> **[PLACEHOLDER: Screenshot of Neurochip hardware constraint analysis]**

---

## 4. Programmatic Verification (Smoke Test)
For developers, a smoke test script is available to verify the API functionality programmatically.

```bash
./scripts/demo_smoke_test.sh
```
This script validates that the backends are healthy and can handle parse, validate, and simulate requests.
