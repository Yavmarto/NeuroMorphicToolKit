# Guide: Multi-Platform Demo — train once, run everywhere

**Goal:** Build and train one simple SNN in the snnTorch Training canvas, then push the trained
weights into every platform CNL Studio can actually reach today — live simulators, notebook
exports, and hardware artifact packages — without leaving the app.

Network: `784 → 256 → 10`, 25 timesteps, MNIST. The 256-neuron hidden layer is the only size
that satisfies both Akida's per-NP limit **and** PYNQ-Z2's synapse budget. Every section below
assumes this shape.

Everything in this guide that is marked **GREEN** was verified working as of **16 August 2026**.
Items marked **YELLOW** need extra setup or have a known caveat. Items marked **RED** will
return an error — do not attempt them.

---

## What "sim panel only" means

The Deploy tab shows a list of target tiles. Clicking a **simulator** tile (snnTorch, Lava,
SC-NeuroCore) opens a **Sim Panel** — tap Play and the backend runs real inference and returns
spike counts and a raster. That bit works.

Clicking **Generate Notebook** for those same targets produces a `.ipynb` file. For snnTorch
the notebook is fully executable. For **Lava** and **SC-NeuroCore**, the generated notebook
cells contain `# TODO: map NIR graph` stub comments — the file is syntactically valid Python
but has no runnable logic. The sim panel and the notebook are two independent code paths; only
the sim panel was finished for those two.

**Practical rule:** if this guide says *sim panel only*, use the Deploy tile's Play button.
Do not generate the notebook and expect it to run.

---

## Before you start

You need the same three `.pt` files as the MNIST FCN guide:

| File | Shape | Use |
|---|---|---|
| `mnist_train.pt` | (9000, 784) | training |
| `mnist_val.pt` | (1000, 784) | validation |
| `mnist_test.pt` | (2000, 784) | final score and Akida eval |

See [GUIDE-mnist-fcn-studio.md](../../2026-07-28/GUIDE-mnist-fcn-studio.md) §0 for how these
are produced. All file pickers below refer to these same files.

In **Setup → Target platform**, tick **all platforms you plan to use** (e.g. `snnTorch`, `Akida`, `PYNQ-Z2`, `Teensy`, `Brian2`, `PyNN`, `Sinabs`, `Rockpool`, `Lava`, `SC-NeuroCore`).

> **Important UI Invariant:** In CNL Studio, **Setup owns the platform list**. The **Deploy** step dropdown strictly filters down to whatever platforms you selected in Step 1 (Setup). If a platform is not ticked during Setup, it will not appear in the Deploy dropdown!


---

## 1. Canvas: Model — `784 → 256 → 10`

| # | Node | Fields to set |
|---|---|---|
| 1 | **Input** | `Size` = **784** |
| 2 | **Linear** | `Rows` = **256**, `Cols` = **784** |
| 3 | **LIF** | `Neurons` = **256**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta (mem decay)` = **0.95** |
| 4 | **Linear** | `Rows` = **10**, `Cols` = **256** |
| 5 | **LIF** | `Neurons` = **10**, same fields as node 3 |
| 6 | **Output** | `Size` = **10** |

Wire: `Input → Linear → LIF → Linear → LIF → Output`.

---

## 2. Canvas: Train

Place these nodes. Nodes 10–12 are the multi-platform exporters — add all three.

| # | Node | Fields to set |
|---|---|---|
| 1 | **Data Loader** (train) | `mnist_train.pt`; `Format` pt; `Batch Size` 128; `Shuffle` on |
| 2 | **State Reset** | none |
| 3 | **Forward Pass** | none |
| 4 | **Time Loop** | `Num Steps` = **25** |
| 5 | **CE Count Loss** | none |
| 6 | **Surrogate Backward** | `Function` fast_sigmoid; `Slope` 25 |
| 7 | **Adam Optimiser** | `Lr` = **0.0005** |
| 8 | **Data Loader** (val) | `mnist_val.pt`; `Format` pt; `Batch Size` 128; `Shuffle` off |
| 9 | **Validation Loop** | `Save Best Checkpoint` on; `Checkpoint Metric` val_accuracy; `Checkpoint Mode` max |
| 10 | **Test Loader** | `mnist_test.pt`; `Format` pt; `Batch Size` 128 — **unwired**, needed by node 11 |
| 11 | **Akida Exporter** | `Filename` model.fbz; `Weight bits` **4**; `Deploy bundle` on; `Eval samples` 2000 |
| 12 | **NIR Exporter** | `Filename` model.nir — **unwired**, leave it as a terminal node |

### Wiring

| From | port | To | port |
|---|---|---|---|
| Data Loader (train) | `data` | Forward Pass | `input` |
| Data Loader (train) | `labels` | CE Count Loss | `labels` |
| State Reset | `model` | Forward Pass | `model` |
| Forward Pass | `spikes` | Time Loop | `spikes` |
| Time Loop | `spikes` | CE Count Loss | `spikes` |
| CE Count Loss | `loss` | Surrogate Backward | `loss` |
| Surrogate Backward | `gradients` | Adam Optimiser | `gradients` |
| Adam Optimiser | `model` | Validation Loop | `model` |
| Adam Optimiser | `model` | Akida Exporter | `model` |

NIR Exporter and Test Loader stay **unwired** (terminal nodes — double-tap to open Inspector
and set their file fields, then leave them disconnected).

The NIR Exporter fires once after the last epoch regardless, reloads `best_model.pt`, and
writes `model.nir` with every trained weight embedded.

---

## 3. Pipeline Settings

- `Epochs` = **5**
- `Batch Size` = **128**
- `Loss Function` = **ce_count**

---

## 4. Canvas: Eval

| # | Node | Fields to set |
|---|---|---|
| 1 | **Data Loader** (test) | `mnist_test.pt`; `Format` pt; `Batch Size` 128; `Shuffle` off |
| 2 | **Time Loop** | `Num Steps` = **25** |
| 3 | **State Reset** | none |
| 4 | **Forward Pass** | none |
| 5 | **Accuracy** | `Top K` = 1 |

Wire: Data Loader `data` → Forward Pass `input`; Data Loader `labels` → Accuracy `labels`;
State Reset `model` → Forward Pass `model`; Forward Pass `spikes` → Accuracy `spikes`.

---

## 5. Train

Generate and run. Expected results at `784 → 256 → 10` (slightly lower than the 1000-unit
variant because the hidden layer is smaller):

| epoch | val accuracy |
|---|---|
| 1 | ~87% |
| 3 | ~91% |
| 5 | ~93% |

The Akida Exporter prints its four-line report after the last epoch. The NIR Exporter writes
`model.nir` alongside `best_model.pt`. Keep both — every section below reads one of them.

---

## 6. What you can do next — platform by platform

After training finishes, go to the **Deploy** step. You will see tiles grouped as simulator,
codegen, and hardware. Work through them in this order.

---

### 6a. snnTorch Sim — GREEN ✅

**What it does:** Live inference in the same PyTorch runtime that trained the network. Spike
raster and output class shown in the panel.

1. Select the **snnTorch** tile.
2. Drop any MNIST image into the input picker (or use the sample from the bundle).
3. Tap **Play**. Spike counts return for all 10 output neurons. The argmax is the predicted class.

No notebook needed — this is the sim panel. Play is enabled because snnTorch is the only target
marked `trainable: true`.

---

### 6b. Lava Sim — YELLOW 🟡 (sim panel only)

**What it does:** Runs the same LIF network through the Intel Lava simulator. Slightly different
spike counts from snnTorch because Lava uses exact integer-step LIF rather than PyTorch's
continuous-time approximation.

**Caveat:** needs `lava-nc` installed in the backend environment. If the tile shows an
`available: false` badge, the Lava package isn't installed — the sim panel returns 503.

1. Select the **Lava** simulator tile.
2. Tap **Play**. The backend dispatches to `LavaSimulatorAdapter`.
3. If you click **Generate Notebook**, the downloaded cells are stubs. Do not try to run it.

---

### 6c. SC-NeuroCore Sim — YELLOW 🟡 (sim panel only)

Same story as Lava: the sim panel dispatches real stochastic-computing inference, the notebook
cells are scaffold stubs. Needs `sc-neurocore` installed.

1. Select the **SC-NeuroCore (Sim)** tile.
2. Tap **Play**.

---

### 6d. Brian2 Notebook — GREEN ✅

**What it does:** Generates a fully runnable Brian2 simulation notebook from the trained NIR
graph. Brian2 uses differential-equation-based LIF — the result is approximate (hardcoded
threshold, ignores v_leak) but close.

1. Select the **Brian2** tile.
2. Click **Generate Notebook**.
3. Open the notebook in Jupyter. It contains real `NeuronGroup` / `Synapses` code, not stubs.
4. Run all cells. Needs `brian2` installed in your Python environment.

> **Known bug:** CubaLIF nodes crash Brian2 export. This network uses plain LIF — no issue.

---

### 6e. PyNN Notebook — GREEN ✅

**What it does:** Generates runnable PyNN code using `IF_curr_exp` neuron model. PyNN is
simulator-agnostic — the same notebook runs against NEURON, NEST, or Brian2 as a backend,
depending on what you have installed.

1. Select the **PyNN** tile.
2. Click **Generate Notebook**.
3. Notebook is real code via `PyNNIO.from_nir()`. Run with `pyNN.brian2` or `pyNN.neuron`.

> **Same CubaLIF bug applies** — no issue with this network.

---

### 6f. Sinabs Notebook — YELLOW 🟡 (feedforward only)

**What it does:** Generates a Sinabs inference notebook targeting SynSense hardware
(Speck / DYNAP-CNN) downstream. Feedforward topologies are faithful; recurrent or branching
topologies raise `NotImplementedError`.

This network is feedforward — you are fine.

1. Select the **Sinabs** tile.
2. Click **Generate Notebook**.
3. Notebook uses `SinabsIO.from_nir()`. Run with `sinabs` installed.

---

### 6g. Rockpool Notebook — YELLOW 🟡 (simple nets only)

**What it does:** Generates a Rockpool notebook for SynSense Speck / DYNAP-CNN. Some node types
raise `NotImplementedError` in the converter. LIF + Linear (this network) is supported.

1. Select the **Rockpool** tile.
2. Click **Generate Notebook**.
3. Run with `rockpool` installed.

---

### 6h. Akida Export — GREEN ✅ (software sim); YELLOW 🟡 (real silicon)

**What it does — software path:** The Akida Exporter node already ran during training and wrote
`model.akida-bundle.zip` and `model.fbz`. This is the real export — `generate_package()` is
fully implemented, runs the Akida software simulator, and prints:

```
snnTorch accuracy : ~93%
Akida accuracy    : ~88%
Conversion delta  : ~5 pp
Deploy bundle     : model.akida-bundle.zip (2000 samples, sha256 ...)
```

No hardware needed for this output.

**What it does — hardware path:** Send that bundle to the physical Akida card.

1. Go to **Results → Deploy to Hardware**.
2. Select **Akida** in the dropdown.
3. Choose **Use Latest Bundle** — it finds `model.akida-bundle.zip` automatically.
4. Progress runs: validate → load → map → evaluate on silicon.

Requires Docker hw-worker running (`hardware` compose profile) plus `akida==2.19.2` on both
the Jupyter server and the paired host. If versions differ the host returns
`MODEL_SDK_VERSION_MISMATCH` — see §10 of the MNIST FCN guide.

---

### 6i. Teensy Firmware Export — GREEN ✅

**What it does:** Generates a compilable Arduino/PlatformIO project ZIP:
`main.ino`, `network_params.h`, `lif_engine.h`, `platformio.ini`. Fully implemented via
Jinja2 templates — real bytes, no stubs. No Teensy board needed to get the ZIP.

**Constraints:** ≤4096 neurons total, feedforward LIF only, no axonal delays, no recurrence.
This network (784+256+10 = 1050 neurons) fits.

1. In the Deploy tab, select the **Teensy 4.1** tile.
2. Click **Export**. The app calls `POST /api/neurochip/export/teensy`.
3. Download the ZIP. Open in PlatformIO and flash — that last step needs hardware.

---

### 6j. PYNQ-Z2 Overlay Export — GREEN ✅ (offline); YELLOW 🟡 (on-board)

**What it does:** Generates an overlay deployment artifact: `overlay_config.json`,
`weights.bin`, `register_map.json`, all in a ZIP. Real bytes — `pynq_generator` is fully
implemented.

**Constraints:** ≤262,144 synapses, ≤1024 neurons/layer, feedforward linear chain.
`784 × 256 = 200,704` + `256 × 10 = 2,560` = **203,264 total** — fits.

> **The `784 → 1000 → 10` network does not fit.** This is why the guide uses 256.

1. Select the **PYNQ-Z2** tile.
2. Click **Export**. The app calls `POST /api/neurochip/export/pynq`.
3. Download the ZIP. On-board deploy is currently blocked pending bitstream build — see
   [GUIDE-pynq-z2-hardware.md](../../2026-08-13/GUIDE-pynq-z2-hardware.md) §9.

---

### 6k. Loihi 2 / Lava Hardware — YELLOW 🟡

**What it does:** `loihi_generator` exists and produces real code, but no E2E test covers this
path and no Loihi 2 board is connected to the dev setup.

1. Select the **Lava / Loihi2** hardware tile.
2. Click **Export**. Returns a Lava Process/ProcessModel package with `Loihi2HwCfg`.
3. On-board execution requires a Loihi 2 board and the Intel NxSDK license.

---

### Do not attempt — RED ❌

| Target | What happens |
|---|---|
| **SpiNNaker** | `POST /api/neurochip/export/spinnaker` raises `NotImplementedError` → HTTP 501 |
| **SpiNNaker 2** | Input/output mapping raises `NotImplementedError` |
| **BrainScaleS** | `POST /api/neurochip/export/brainscales` raises `NotImplementedError` → HTTP 501 |
| **Nengo** | Notebook generates, but this target is marked legacy and not part of the active product surface |
| **Neurohub** | Router commented out in `suite_api/main.py` — unreachable |

---

## 7. Summary table

| Platform | Path in app | Demo today? |
|---|---|---|
| **snnTorch** | Deploy → snnTorch tile → Play | ✅ Green |
| **Lava sim** | Deploy → Lava tile → Play | 🟡 Needs lava-nc |
| **SC-NeuroCore sim** | Deploy → SC-NeuroCore tile → Play | 🟡 Needs sc-neurocore |
| **Brian2 notebook** | Deploy → Brian2 tile → Generate Notebook | ✅ Green |
| **PyNN notebook** | Deploy → PyNN tile → Generate Notebook | ✅ Green |
| **Sinabs notebook** | Deploy → Sinabs tile → Generate Notebook | 🟡 Feedforward only |
| **Rockpool notebook** | Deploy → Rockpool tile → Generate Notebook | 🟡 Simple nets only |
| **Akida (software)** | Training Akida Exporter node runs automatically | ✅ Green |
| **Akida (silicon)** | Results → Deploy to Hardware → Akida | 🟡 Needs hw-worker |
| **Teensy 4.1 ZIP** | Deploy → Teensy tile → Export | ✅ Green |
| **PYNQ-Z2 ZIP** | Deploy → PYNQ-Z2 tile → Export | ✅ Green (offline) |
| **Loihi 2 hardware** | Deploy → Lava/Loihi2 tile → Export | 🟡 No board connected |
| **SpiNNaker / SpiNNaker2 / BrainScaleS** | — | ❌ Red — 501 error |

One trained network (`784 → 256 → 10`) reaches **10 distinct platforms** from a single app session.
Five are fully green with no hardware required.

---

## 8. If something looks wrong

| Symptom | Cause |
|---|---|
| Lava / SC-NeuroCore tile shows `available: false` badge | Package not installed in backend — yellow, not red |
| Akida Exporter prints `near 10% accuracy` | Weight scaling issue in conversion — conversion delta warning; not a training problem |
| PYNQ export returns synapse budget error | Hidden layer > 512 neurons or network is not feedforward |
| Teensy export returns `network too large` | Total neurons > 4096 or a recurrent edge exists |
| SpiNNaker export returns HTTP 501 | Expected — generator is a stub, do not attempt |
| Lava notebook cells are `# TODO` | Expected — notebook codegen is a stub; use the sim panel instead |

---

Last verified: **16 August 2026**.
