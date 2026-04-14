# NeuroMorphicToolkit (NMTK) Demo Walkthrough

This walkthrough is the simplest supported demo path:

1. Launch NeuroCNL
2. Paste a valid CNL
3. Validate it
4. Run the simulation
5. Click `Open in NeuroSim`
6. Confirm NeuroSim opens with the canvas already populated

`Export` is optional. It is for saving files, not for moving the design into NeuroSim.

---

## 1. Environment Setup

### 1.1 Start the Backends

Recommended:

```bash
docker compose up -d
```

Or start the three demo services individually:

```bash
cd neurocnl && docker compose up -d
cd Neurosim && docker compose up -d
cd Neurochip && docker compose up -d
```

Verify the services:

```bash
curl -s http://localhost:8000/health   # neurocnl
curl -s http://localhost:8001/health   # neurosim
curl -s http://localhost:8002/health   # neurochip
```

Expected result:

```json
{"status":"ok"}
```

### 1.2 Open the Launcher

```bash
cd nmtk/neuro_toolkit
flutter run -d macos
```

You can use another supported Flutter desktop target if needed.

---

## 2. Canonical Demo Flow

### 2.1 Open NeuroCNL

1. In the launcher catalog, install and launch `CNL Studio` if needed.
2. Wait for the embedded NeuroCNL page to load.

You should see:

- a CNL editor on the left
- results tabs on the right
- `Run Simulation`
- `Open in NeuroSim`
- `Export`

### 2.2 Paste a Valid CNL

Use this exact demo spec:

```text
# Simple Reflex Arc
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5
The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.7
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 2.0
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The sensory neuron MUST NOT fire DURING the refractory period of 0.01 seconds
```

### 2.3 Validate

NeuroCNL validates as you work. Confirm the validation panel reports success before continuing.

What to look for:

- validation passes overall
- no blocking parse errors
- the network and simulation tabs become meaningful for this spec

### 2.4 Run Simulation

1. Click `Run Simulation`.
2. Wait for the run to finish.
3. Confirm the simulation tab shows spike and timing results.

The important checkpoint is simple:

- the CNL is valid
- the simulation completes successfully

### 2.5 Open in NeuroSim

1. Click `Open in NeuroSim`.
2. The launcher should switch to the NeuroSim tab automatically.
3. NeuroSim should open with:
   - the imported CNL already present in the CNL panel
   - the canvas already populated from that CNL
   - a success banner confirming the import

This is the intended handoff. You do **not** need to export a file first.

If the canvas is still empty, the flow is not working correctly.

### 2.6 Confirm the NeuroSim State

Once NeuroSim opens, confirm:

- the canvas is not empty
- at least the imported reflex-arc nodes are visible
- the CNL panel contains the imported text
- the import banner confirms the handoff worked

If NeuroSim cannot parse the incoming spec, it should:

- keep the imported text visible in the CNL panel
- keep the canvas empty
- show a clear banner telling you to fix the CNL and click `Sync to Canvas`

---

## 3. Optional Artifact Export

Use `Export` only if you want to save files such as:

- `.cnl`
- HTML report
- Python/Nengo script
- hardware/export artifacts

Expected behavior:

- the current NeuroCNL page stays visible
- a file download starts, or a clear fallback message appears
- the export should **not** replace the entire page with raw text

If clicking `Export` turns the whole embedded page into plain text, that is a bug.

---

## 4. Optional Follow-On Module Checks

### 4.1 NeuroSim

After the one-click handoff succeeds, you can continue in NeuroSim by:

- inspecting the imported graph
- editing the imported CNL and clicking `Sync to Canvas`
- running further preview or export actions from NeuroSim

### 4.2 Neurochip

You can also open Neurochip separately to inspect hardware-oriented workflows after the simulation and NeuroSim handoff are complete.

---

## 5. Programmatic Smoke Test

For API-only verification:

```bash
./scripts/demo_smoke_test.sh
```

This checks the NeuroCNL parse, validate, and simulate pipeline, but it does not verify the launcher handoff UX.

---

## 6. Troubleshooting

### `Open in NeuroSim` does nothing

- Confirm both `http://localhost:8000/health` and `http://localhost:8001/health` return healthy responses.
- If you are inside the launcher, make sure NeuroSim can be launched from the catalog.
- If needed, use the launcher `Open in System Browser` button and retry from there.

### NeuroSim opens but the canvas is empty

- This means the handoff did not populate the graph correctly.
- Check whether the imported CNL is visible in the NeuroSim CNL panel.
- If the text is present but the graph is empty, NeuroSim should show an import error banner and you can try `Sync to Canvas`.

### Export shows raw text in the page

- That is incorrect behavior.
- The page should remain in NeuroCNL and either download the file or show a fallback message.

### Port already in use

```bash
lsof -ti:8000 | xargs kill -9
lsof -ti:8001 | xargs kill -9
lsof -ti:8002 | xargs kill -9
```

### Docker services fail to start

```bash
docker compose logs neurocnl
docker compose logs neurosim
docker compose logs neurochip
```

### Launcher does not start

```bash
cd nmtk/neuro_toolkit
flutter doctor
flutter clean
flutter pub get
flutter run -d macos
```
