# Quick Start

In this guide you will write a simple spiking neural network in plain English, validate it, run a simulation, and open the result on the NeuroStudio visual canvas — all in about five minutes.

**Prerequisites:** NMTK is installed and the backends are running. If not, complete the [Installation](installation.md) guide first.

---

## 1. Start the backends

=== "Docker"

    ```bash
    docker compose up -d
    ```

    Wait until healthy:

    ```bash
    curl -s http://localhost:9000/api/suite/health
    # Expected: {"status":"ok", ...}
    ```

=== "Manual"

    ```bash
    source .venv/bin/activate
    uvicorn suite_api.main:app --reload --port 9000
    ```

---

## 2. Open the launcher

```bash
cd nmtk/neuro_toolkit
flutter run -d macos
```

The launcher dashboard appears. If this is your first time, a welcome walkthrough guides you through the Dashboard, Catalog, and Workspace tabs.

---

## 3. Install and launch NeuroStudio

1. Click the **Catalog** tab.
2. Find **CNL Studio** (NeuroStudio) and click **Install**.
   The launcher creates a Python venv and installs the module — this takes about 30 seconds the first time.
3. Once status changes to **Installed**, click **Launch**.
   The NeuroStudio interface loads in the embedded workspace.

You should see:

- A CNL editor panel on the left
- Results tabs (Network, Simulation, Export) on the right
- Buttons: **Run Simulation** · **Open in NeuroStudio** · **Export**

---

## 4. Write your first SNN

Paste this specification into the CNL editor:

```text
# Simple Reflex Arc
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5
The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.7
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 2.0
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The sensory neuron MUST NOT fire DURING the refractory period of 0.01 seconds
```

NeuroStudio validates as you type. Watch the **Validation** panel:

- Green checkmark — spec is well-formed and biologically consistent
- Amber warning — non-blocking issue (simulation will still run)
- Red error — blocking parse or constraint violation; fix before continuing

!!! tip "What is CNL?"
    Controlled Natural Language (CNL) is NMTK's plain-English SNN specification format. You describe neurons, connections, and constraints in structured sentences — the compiler handles the translation to a verified spiking model. See [NeuroStudio](../modules/neurostudio.md) for the full syntax reference.

---

## 5. Run the simulation

1. Confirm the validation panel shows no blocking errors.
2. Click **Run Simulation**.
3. Wait for the job to complete (typically a few seconds for this spec).
4. Click the **Simulation** results tab.

You should see spike timing data for the sensory and motor neurons confirming the reflex arc fires as specified.

---

## 6. Open on the visual canvas

1. Click **Open in NeuroStudio**.
2. The Launcher switches to the NeuroStudio canvas automatically — no file export needed.
3. Confirm the canvas shows:
   - The reflex arc nodes (sensory neuron → motor neuron connection)
   - The imported CNL text in the side panel
   - A confirmation banner: *Import successful*

From the canvas you can inspect the graph, edit the CNL and click **Sync to Canvas**, or run further preview and export actions.

!!! warning "Canvas is empty after handoff?"
    This means the CNL did not parse into a graph. The CNL panel will still contain your text — click **Sync to Canvas** after fixing any errors shown in the banner. See [Troubleshooting](../troubleshooting.md#neurostudio-opens-but-the-canvas-is-empty) for details.

---

## 7. Optional: export an artifact

Click **Export** if you want to save the result as a file:

| Format | Use case |
|--------|---------|
| `.cnl` | Re-import into any NMTK instance |
| HTML report | Share a rendered summary |
| Python / Nengo script | Use outside NMTK |
| Hardware artifact | Pass to Neurochip for deployment |

Export is not required to continue working in the canvas.

---

## What's next?

- **Simulate with physics** — restart Docker with `--profile physics` to enable MuJoCo-backed dynamics
- **Deploy to hardware** — follow the [Simulation to Hardware](../workflows/simulation-to-hardware.md) workflow
- **Run a benchmark** — open Neurobench, import your model, and compare against community baselines in [Neurohub](../modules/neurohub.md)
- **Encode real sensor data** — [Neurosense](../modules/neurosense.md) converts EMG, vision, and audio signals into spike trains ready for your network
