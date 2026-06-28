# CNLStudio Notebook Reverse-Engineering Analysis Report

**Date:** 16 June 2026 · **Updated:** 27 June 2026  
**Scope:** `paper/01_lif`, `paper/02_cnn`, `paper/03_rnn` — 6 notebooks  
**Target UI:** CNLStudio (Model → Training → Eval → Hardware Deployment → Results)

---

## Summary Table

| Notebook | Purpose | Viability | Primary Blocker |
|----------|---------|-----------|-----------------|
| `01_lif/lif_snntorch.ipynb` | LIF inference from NIR | 🟢 HIGH | Missing Spike Generator and Spike Rate Logger |
| `02_cnn/snntorch_apply.ipynb` | CNN-SNN inference on NMNIST | 🟢 HIGH | None |
| `03_rnn/Braille_training_snntorch.ipynb` | Full RNN training (Braille) | 🟢 HIGH | None |
| `03_rnn/snntorch_apply_subtract.ipynb` | Braille inference (subtract reset) | 🟢 HIGH | None |
| `03_rnn/nengo_apply.ipynb` | Nengo simulation via NIR | 🟡 MODERATE | Custom `nir_to_nengo` converter (moderate) |
| `03_rnn/plots.ipynb` | Cross-framework activity comparison | ⬜ VERY LOW | Not a training/inference workflow |

---

## Notebook 1: `paper/01_lif/lif_snntorch.ipynb`

### Notebook Purpose

Loads a pre-trained single LIF neuron from a NIR file (`lif_norse.nir`, originally trained in Norse), runs it forward on a synthetic spike train for 100 timesteps using snnTorch, and plots the output spike raster and membrane potential. Outputs results to `lif_snntorch.csv`.

**Architecture:**
```
Input (1) → Affine (1×1, no bias) → LIF (tau=0.0025, r=1.0, v_threshold=0.1) → Output (1)
```

### Viability Analysis

**Verdict: 🟢 HIGH — Minor missing node implementations**

This notebook is structurally mappable to CNLStudio. All layer types (Affine/Linear + LIF) are in the Model canvas palette and NIR import is supported. However, the required synthetic spike train cannot be generated currently as there is no Spike Generator node, and the results cannot be evaluated out of the box because the Spike Rate Logger node is not fully implemented.

**Blockers:**

| # | Blocker | Severity | Workaround |
|---|---------|----------|-----------|
| 1 | Synthetic input data is a hand-crafted ISI spike train — CNLStudio has no native "Spike Train Generator" node | Major | Needs to be built. Currently there is no `Spike Generator` in the Data canvas palette. |
| 2 | Missing "Spike Rate Logger" node | Major | Needs to be built. Cannot currently capture output spikes per timestep natively in the Eval Canvas. |
| 3 | Lack of clear connection topology in UI | Minor | Some nodes have 2 output ports. Needs clarification on which node connects to which node in documentation or UI helpers. |

### UI Replication Guide

*Note: This guide describes the workflow once the missing features (Spike Generator, Spike Rate Logger) are implemented.*

**Canvas: Model**

1. Open CNLStudio → navigate to the **Model Canvas**.
2. Use the **Export / File Menu** → **Import NIR...** and select `lif_norse.nir`. The graph will be built automatically.

**Canvas: Eval**

8. Navigate to the **Eval Canvas**.
9. Add a **Spike Generator** node (Data palette). Configure: `n_neurons=1`, `n_timesteps=100`, `pattern=isi_regular`, `isi_period=10`, `seed=42`. This replicates the notebook's hand-crafted ISI spike train (`_spikes[9::10] = 1.0`) without any external data generation.
10. Add a **State Reset** node (resets LIF hidden state at start of each sample).
11. Add a **Forward Pass** node in `eval_mode = true`.
12. Add a **Spike Rate Logger** node to capture output spikes per timestep.
13. Connect the node ports as follows:
    - **Spike Generator** (`data`) → **Forward Pass** (`input`)
    - **State Reset** (`model` out) → **Forward Pass** (`model` in)
    - **Forward Pass** (`spikes`) → **Spike Rate Logger** (`spikes`)
    *(Note: Any remaining output ports, such as `membrane` and `model` on the Forward Pass node, should be left unconnected.)*
14. Click **Run Eval**.

**Results Step: Dynamics Tab**

15. After the eval run completes, navigate to the **Results** step and open the **Dynamics** tab.
16. The **Spike Raster** panel will display the output spike times (equivalent to `axs[0].eventplot(...)` in the notebook).
17. The **Membrane Voltage Trace** panel will display the LIF membrane potential over 100 timesteps (equivalent to `axs[1].plot(mem_arr)`).
18. Export results to CSV via the export button if needed (replicates `lif_snntorch.csv`).

---

## Notebook 2: `paper/02_cnn/snntorch_apply.ipynb`

### Notebook Purpose

Loads a pre-trained CNN-based SNN from `cnn_sinabs.nir` (originally trained in Sinabs), evaluates it on the NMNIST test set (loaded via the `tonic` library), and achieves 97.85% accuracy. Also extracts and saves first-layer spike activity as `snnTorch_activity.npy`.

**Architecture (from NIR):**
```
Input (2×34×34) → Conv2d(2→16, 5×5, stride=2, pad=1) → LIF
                → Conv2d(16→16, 3×3, pad=1) → LIF → AvgPool2d(2×2)
                → Conv2d(16→8, 3×3, pad=1) → LIF → AvgPool2d(2×2)
                → Flatten → Linear(128→256) → LIF → Linear(256→10) → LIF → Output
```
5 LIF neurons total (one after each Conv2d, one after each Linear).

### Viability Analysis

**Verdict: 🟢 HIGH — fully buildable and reproducible**

All layer types are in the CNLStudio Model canvas palette and NIR import works. The `tonic` integration for NMNIST is also supported natively via the Data Loader node. Results visualization is fully supported in the Results step Dynamics tab.

**Blockers:**

| # | Blocker | Severity | Workaround |
|---|---------|----------|-----------|
| 1 | `tonic.datasets.NMNIST` — CNLStudio requires pre-downloaded datasets | Minor | The Data Loader node may lack an auto-download toggle for tonic. You might need to manually trigger the tonic download to the data directory before running. |
| 2 | Model loaded from `cnn_sinabs.nir` | ✅ **Fixed** | "Import NIR..." option now available in the export/file menu. |
| 3 | `snn.Leaky` in the notebook corresponds to LIF with `r=1, v_leak=0` | Minor | Set LIF `tau` to match the Leaky `beta` parameter: `tau = -dt / ln(beta)` |
| 4 | Accuracy computed as mean over batches of argmax-of-mean-over-time | Negligible | Use top-1 Accuracy metric with spike count summation |
| 5 | Layer-1 spike activity visualization | ✅ **Fixed** | Layer-1 spike raster activity is viewable in the Results step → Dynamics tab after running eval. |
| 6 | Lack of clear connection topology in UI | Minor | Some nodes have multiple output ports. UI needs clarify on proper routing. |

### UI Replication Guide

**Canvas: Model**

1. Open the **Model Canvas**.
2. Use the **Export / File Menu** → **Import NIR...** and select `cnn_sinabs.nir`. The entire CNN topology and pre-trained weights will be imported automatically.

**Canvas: Eval**

3. Navigate to the **Eval Canvas**.
4. Add a **Data Loader** node. Set format to `tonic_nmnist`, `time_window_ms=1.0`. Set `batch_size=128`.
5. Add a **State Reset** node.
6. Add a **Forward Pass** node: `eval_mode=true`.
7. Add an **Accuracy** node: `top_k=1`. The canvas will compute accuracy via spike count argmax across timesteps.
8. Connect the node ports as follows:
   - **Data Loader** (`data`) → **Forward Pass** (`input`)
   - **Data Loader** (`labels`) → **Accuracy** (`labels`)
   - **State Reset** (`model` out) → **Forward Pass** (`model` in)
   - **Forward Pass** (`spikes`) → **Accuracy** (`spikes`)
   *(Note: Any remaining output ports, such as `membrane` and `model` on the Forward Pass node or `metrics` on the Accuracy node, should be left unconnected.)*
9. Click **Run Eval**. Expected result: ~97.85%.

**Results Step: Dynamics Tab**

10. After the eval run completes, navigate to the **Results** step and open the **Dynamics** tab.
11. Select the first **LIF** node in the graph. The **Spike Raster** panel will show layer-1 activity over time (equivalent to `act` saved in the notebook as `snnTorch_activity.npy`, shape `[T, B, 16, 16, 16]`).
12. Use the export button to save activity arrays to `.npy` if needed.

---

## Notebook 3: `paper/03_rnn/Braille_training_snntorch.ipynb`

### Notebook Purpose

Full end-to-end **training** of a spiking RNN for Braille gesture recognition. Classifies 7 letter categories (Space, A, E, I, O, U, Y) from 12-channel tactile spike inputs over 256 timesteps. Uses recurrent synaptic neurons (`RSynaptic` hidden layer, `Synaptic` output layer), surrogate gradient backpropagation, CE count loss, and L1/L2 spike regularization. Trains for 500 epochs with Adam optimizer, saves best checkpoint by validation accuracy.

**Architecture:**
```
Input (12) → Linear(12 → N_hidden, no bias)
           → RSynaptic(alpha_r, beta_r, recurrent=True, reset="subtract") [N_hidden]
           → Linear(N_hidden → 7, no bias)
           → Synaptic(alpha_out, beta_out, reset="subtract") [7]
           → Output (7)
```
Where `N_hidden`, `alpha_r`, `beta_r`, `alpha_out`, `beta_out` are loaded from `data/parameters_noDelay_noBias_ref_subtract.json`.

### Viability Analysis

**Verdict: 🟢 HIGH — fully reproducible**

> ✅ **UI Fixes Shipped:** `cnl.RSynaptic`, `cnl.Synaptic`, surrogate gradient slope, L1/L2 regularizers, and Dynamics monitoring are now fully supported in CNLStudio. The Braille datasets and parameter files are present in the `paper/03_rnn/data` directory.

**Blockers:**

| # | Blocker | Severity | Notes |
|---|---------|----------|-------|
| 1 | `cnl.RSynaptic` and `cnl.Synaptic` nodes | ✅ **Fixed** | Now available in palette with correct parameters. |
| 2 | L1/L2 spike regularization | ✅ **Fixed** | `l1SpikeReg` and `l2SpikeReg` nodes added to Training canvas palette. |
| 3 | Surrogate gradient slope | ✅ **Fixed** | Exposed in `surrogateBackward` node. |
| 4 | Missing hyperparameters JSON file | ✅ **Fixed** | Present in repo (`parameters_noDelay_noBias_ref_subtract.json`). |
| 5 | Missing Braille datasets | ✅ **Fixed** | Present in repo (`ds_train.pt`, `ds_val.pt`, `ds_test.pt`). |
| 6 | Live training metrics visualization | ✅ **Fixed** | Loss curves and validation accuracy are shown live in the Training step; layer spike rasters are viewable in the Results step → Dynamics tab after training completes. |
| 7 | Complex connection topologies not fully clear | Minor | Large training topologies might be difficult to wire without clear UI indicators for multi-port nodes. |

**Closest approximation:**

The notebook maps cleanly to all 4 canvases (Model, Training, Eval, Hardware Deployment). The full training pipeline (Adam + CE count loss + BPTT + L1/L2 reg + 500 epochs) is well-supported in CNLStudio's Training canvas; post-run inspection lives in the Results step.

### UI Replication Guide

**Canvas: Model**

1. Open the **Model Canvas**.
2. Add an **Input** node: `n_neurons = 12`.
3. Add a **Linear** node: `in_features=12`, `out_features=N_hidden` (from JSON), disable bias.
4. Add a **cnl.RSynaptic** node: `alpha=alpha_r`, `beta=beta_r`, `reset_mechanism="subtract"`, `use_bias=false`. The internal recurrent Linear layer is built in — no separate recurrent edge needed.
5. Add a **Linear** node: `in_features=N_hidden`, `out_features=7`, disable bias.
6. Add a **cnl.Synaptic** node: `alpha=alpha_out`, `beta=beta_out`, `reset_mechanism="subtract"`.
7. Add an **Output** node: `n_neurons=7`.
8. Connect: **Input → Linear#1 → cnl.RSynaptic → Linear#2 → cnl.Synaptic → Output**.

**Canvas: Training**

9. Navigate to the **Training Canvas**.
10. Add a **Data Loader** node: set `format=pt`, `dataset_path=paper/03_rnn/data/ds_train.pt`, `batch_size=64`, `shuffle=true`. The `.pt` format is now natively supported — no conversion needed.
11. Add a **State Reset** node (resets cnl.RSynaptic and cnl.Synaptic states at each batch start).
12. Add a **Forward Pass** node with `num_steps=256` (time dimension from dataset).
13. Add a **CE Count Loss** node (equivalent to `SF.ce_count_loss()`).
14. Add **l1SpikeReg** node: `weight=reg_l1`, applied to cnl.RSynaptic layer.
15. Add **l2SpikeReg** node: `weight=reg_l2`, applied to cnl.RSynaptic layer.
16. Add a **Backward Pass (Surrogate Gradient)** node: algorithm = `fast_sigmoid`, `slope=slope` value from JSON.
17. Add an **Adam Optimizer** node: `lr=lr` from JSON, `betas=(0.9, 0.999)`.
18. Connect the node ports as follows:
    - **Data Loader** (`data`) → **Forward Pass** (`input`)
    - **Data Loader** (`labels`) → **CE Loss** (`labels`)
    - **State Reset** (`model` out) → **Forward Pass** (`model` in)
    - **Forward Pass** (`spikes`) → **CE Loss** (`spikes`)
    - **Forward Pass** (`model` out) → **Backward Pass** (`model` in)
    - **CE Loss** (`loss`) → **Backward Pass** (`loss`)
    - **Backward Pass** (`model` out) → **Optimizer** (`model` in)
    *(Note: Any remaining output ports, such as `membrane` on the Forward Pass node, should be left unconnected.)*
19. Set **Epochs = 500** in the Training canvas header.
20. Enable **Best Checkpoint Save** (saves weights at epoch with highest validation accuracy).
21. Add a second **Data Loader** for the validation set: `format=pt`, `dataset_path=paper/03_rnn/data/ds_val.pt`, `batch_size=64`, `shuffle=false`. Connect to a **Validation Loop** node.
22. Click **Start Training**.

**Canvas: Eval**

23. After training completes, navigate to the **Eval Canvas**.
24. Add a **Data Loader** for the test set: `format=pt`, `dataset_path=paper/03_rnn/data/ds_test.pt`, `batch_size=64`, `shuffle=false`.
25. Load the best checkpoint weights via **Load Checkpoint**.
26. Add **State Reset**, **Forward Pass** (eval_mode=true), and **Accuracy** nodes. Connect the ports:
    - **Data Loader** (`data`) → **Forward Pass** (`input`)
    - **Data Loader** (`labels`) → **Accuracy** (`labels`)
    - **State Reset** (`model` out) → **Forward Pass** (`model` in)
    - **Forward Pass** (`spikes`) → **Accuracy** (`spikes`)
    *(Note: Any remaining output ports, such as `membrane` and `model` on the Forward Pass node or `metrics` on the Accuracy node, should be left unconnected.)*
    Run the evaluation.
27. Expected result: ~92% test accuracy (subtract reset, no bias, no delay configuration).

**Canvas: Hardware Deployment**

28. To save trained weights: navigate to **Hardware Deployment**.
29. Select **NIR Exporter** — exports the trained model as `braille_noDelay_noBias_subtract.nir` (the NIR file consumed by notebooks 4 and 5).
30. Optionally select **Python Exporter** or **TorchScript Exporter** for standalone inference.

**Training Step: Live Metrics**

31. During training, the Training step displays a **live loss curve** and **validation accuracy curve** per epoch — no additional navigation required.

**Results Step: Dynamics Tab (post-run)**

32. After training completes, navigate to the **Results** step and open the **Dynamics** tab.
33. View the **Spike Raster** from the cnl.RSynaptic hidden layer to inspect spike activity patterns (equivalent to `hid_rec` tracked in the notebook).

---

## Notebook 4: `paper/03_rnn/snntorch_apply_subtract.ipynb`

### Notebook Purpose

Inference-only evaluation of the pre-trained Braille RNN model using the **subtract** reset mechanism. Loads pre-trained weights from `data/model_noDelay_noBias_ref_subtract.pt`, runs against the full test set, reports 92.14% accuracy, and performs 10 single-sample inference runs showing per-class label probabilities.

**Architecture:** Identical to Notebook 3 (RSynaptic + Synaptic). Key difference: inference only, no training.

### Viability Analysis

**Verdict: 🟢 HIGH — fully reproducible**

> ✅ **UI Fixes Shipped:** `cnl.RSynaptic` and `cnl.Synaptic` now fully support the required `reset_mechanism="subtract"` parameter. The pre-trained checkpoint, test dataset, and monitoring capabilities are available.

**Blockers:**

| # | Blocker | Severity | Notes |
|---|---------|----------|-------|
| 1 | `RSynaptic` + `Synaptic` with subtract reset | ✅ **Fixed** | Available directly in the node property panels. |
| 2 | Missing pre-trained `.pt` weights | ✅ **Fixed** | Present in repo (`model_noDelay_noBias_ref_subtract.pt`). |
| 3 | Missing Braille dataset | ✅ **Fixed** | Present in repo (`ds_test.pt`). |
| 4 | Label probability visualization | ✅ **Fixed** | Label probabilities are supported natively via horizontal bar chart in the Results step → Dynamics tab. |

This notebook maps entirely to the Eval canvas (one-shot inference run); label probability display is shown in the Results step. Build the model as per Notebook 3, then run Eval.

### UI Replication Guide

**Canvas: Model**

1. Reconstruct the model as described in Notebook 3, steps 1–8 (`cnl.RSynaptic` + `cnl.Synaptic` — now available).

**Canvas: Hardware Deployment**

2. Navigate to **Hardware Deployment**.
3. Select **NIR Importer** or **Weight Loader**. Load the pre-trained weights from `data/model_noDelay_noBias_ref_subtract.pt`. If the model was previously trained via CNLStudio (Notebook 3), load the saved checkpoint directly.

**Canvas: Eval**

4. Navigate to the **Eval Canvas**.
5. Add a **Data Loader**: `format=pt`, `dataset_path=paper/03_rnn/data/ds_test.pt`, `batch_size=64`, `shuffle=false`.
6. Add **State Reset**, **Forward Pass** (eval_mode=true), and **Accuracy** nodes. Connect the ports:
   - **Data Loader** (`data`) → **Forward Pass** (`input`)
   - **Data Loader** (`labels`) → **Accuracy** (`labels`)
   - **State Reset** (`model` out) → **Forward Pass** (`model` in)
   - **Forward Pass** (`spikes`) → **Accuracy** (`spikes`)
   *(Note: Any remaining output ports, such as `membrane` and `model` on the Forward Pass node or `metrics` on the Accuracy node, should be left unconnected.)*
7. Click **Run Eval**. Expected: ~92.14% test accuracy.

**Single-sample inference (label probabilities):**

8. In the Eval Canvas, add a **Data Loader**: `format=pt`, `dataset_path=paper/03_rnn/data/ds_test.pt`, `batch_size=1`, `shuffle=true`.
9. Add a **State Reset**, **Forward Pass** node, and a **Softmax** output node. Connect the ports:
   - **Data Loader** (`data`) → **Forward Pass** (`input`)
   - **State Reset** (`model` out) → **Forward Pass** (`model` in)
   - **Forward Pass** (`spikes`) → **Softmax** (`input`)
   *(Note: Any remaining output ports, such as `membrane` and `model` on the Forward Pass node or `output` on the Softmax node, should be left unconnected.)*
10. Run 10 times and observe the label probability output in the **Results step → Dynamics tab** (horizontal bar chart) — this replicates the notebook's `lbl_probs` printout, showing confidence per letter (Space, A, E, I, O, U, Y).

---

## Notebook 5: `paper/03_rnn/nengo_apply.ipynb`

### Notebook Purpose

Runs the trained Braille model through the **Nengo** neural simulator. Loads `braille_noDelay_noBias_subtract.nir`, converts it to a Nengo network using the custom `nir_to_nengo` module, simulates 256 timesteps per sample, and evaluates accuracy on the full test set. Also plots a comparison of hidden-layer activity between Norse and Nengo to validate cross-framework consistency.

### Viability Analysis

**Verdict: 🟡 MODERATE — Nengo deployment path unblocked; monitoring and caveats remain**

> ✅ **UI Fixes Shipped:** `cnl.RSynaptic` export serialization and Nengo simulation parameters (`nengo_dt`, `nengo_presentation_time`) are now supported. The required test dataset is available.

**Blockers:**

| # | Blocker | Severity | Notes |
|---|---------|----------|-------|
| 1 | Missing Braille dataset | ✅ **Fixed** | Present in repo (`ds_test.pt`). |
| 2 | `nir_to_nengo` custom converter for `cnl.RSynaptic` | Moderate | CNLStudio's Nengo deployment contract must handle `cnl.RSynaptic` node type. |
| 3 | Canvas preview missing Nengo simulation for RSynaptic | Moderate | Nengo converter extension is still pending for full preview capabilities. |
| 4 | Nengo simulation result visualization | Minor | Results must be viewed externally or via `.npy` import into the Results step → Dynamics tab. |
| 5 | Post-simulation activity export | ✅ **Fixed** | Activity can be exported/viewed natively from the Results step → Dynamics tab (`.npy` zip export). |

With `cnl.RSynaptic` and `cnl.Synaptic` now in both the Model palette and NIR export schema, this notebook maps as follows:

### UI Replication Guide

**Canvas: Model**

1. Build the Braille model as per Notebook 3, steps 1–8 (Input → Linear → cnl.RSynaptic → Linear → cnl.Synaptic → Output). Now available.
2. Alternatively, if the model was already trained (Notebook 3), load the saved NIR export — skip to step 4.

**Canvas: Hardware Deployment**

3. Navigate to **Hardware Deployment**.
4. In the deployment target catalog, select **Nengo** (NIR-native framework target).
5. Configure the Nengo target settings:
   - `dt = 1e-4` (simulation timestep matching the notebook)
   - `presentation_time = 1e-4` (one input frame per Nengo timestep)
6. Click **Export / Deploy to Nengo**. CNLStudio will:
   - Export the model graph as a NIR `.nir` file.
   - Convert NIR → Nengo network (via the CNLStudio deployment contract, equivalent to `nir_to_nengo.nir_to_nengo(graph, dt=dt)`).
   - Wire up stimulus input and output probes.

**Running the simulation:**

7. The Nengo simulation runs outside CNLStudio (in a standard Nengo environment). The notebook's simulation loop is:
   ```python
   sim = nengo.Simulator(model, dt=dt)
   sim.run(dt * 256)
   output = np.argmax(np.mean(sim.data[p_output], axis=0))
   ```
   This corresponds to a 256-step simulation for each of the 1030 test samples.

**Results Step: Post-simulation activity (partial):**

8. After simulation completes, hidden-layer activity (`p_lif1`) is saved as `nengo_activity_noDelay_noBias_subtract.npy`.
9. To view activity in CNLStudio: import the `.npy` file as a custom spike raster overlay in the **Results step → Dynamics tab** (if `.npy` import for visualization is supported — not yet confirmed). Otherwise, use Nengo's own plotting tools or the `plots.ipynb` notebook for the cross-framework activity comparison.

---

## Notebook 6: `paper/03_rnn/plots.ipynb`

### Notebook Purpose

Pure research visualization notebook. Loads hidden-layer activity arrays (`.npy` files) from 8 SNN frameworks (Lava, Nengo, Norse, Rockpool, snnTorch, SpiNNaker2, Spyx, Xylo), computes pairwise cosine similarity between framework activities, and generates publication-quality PDF heatmaps comparing the activity consistency across frameworks. Also visualizes the raw Braille input spike pattern.

### Viability Analysis

**Verdict: ⬜ VERY LOW — research visualization tool, not a CNLStudio UI workflow**

This notebook is not a model training or inference workflow; it is a post-hoc analysis tool that aggregates results from multiple frameworks and generates comparison figures. CNLStudio's Results step is designed for single-run visualization of one model, not cross-framework comparison.

**Blockers:**

| # | Blocker | Severity | Notes |
|---|---------|----------|-------|
| 1 | Cross-framework cosine similarity comparison — CNLStudio has no concept of comparing activity from 8 different simulators | **By design** | This is a research artifact tool, out of scope for a UI canvas |
| 2 | Output is publication PDF figures (`rnn_similarity.pdf`, `rnn_nobias.pdf`, etc.) — CNLStudio does not produce static figures | By design | CNLStudio produces interactive plots, not static publication figures |
| 3 | Inputs are `.npy` activity files from multiple external runs — CNLStudio does not aggregate results from external simulators | By design | — |

**Partial mapping:**

The following elements of `plots.ipynb` do have partial analogs in CNLStudio:

| Notebook element | CNLStudio analog |
|-----------------|-----------------|
| `a0.imshow(d.T)` — Braille input spike pattern (12 neurons × 256 timesteps) | **Results step → Dynamics tab → Spike Raster**: shows input neuron activity as a raster. Select the Input node after running an eval/simulation. |
| Per-framework activity visualization (hidden layer spike rasters) | **Results step → Dynamics tab → Spike Raster**: select the cnl.RSynaptic hidden layer node. One framework at a time only. |
| Accuracy per framework | **Eval canvas → Accuracy metric**: run eval separately for each target in Hardware Deployment and note the accuracy. No automatic aggregation across targets. |

### UI Replication Guide (Partial)

**Eval Canvas + Results Step (for Braille input visualization)**

1. In the Eval Canvas, run inference on a single Braille test sample (`batch_size=1`).
2. Navigate to the **Results** step and open the **Dynamics** tab. Select the **Input** node in the network graph.
3. The Spike Raster panel shows the 12-neuron input pattern over 256 timesteps — equivalent to `a0.imshow(d.T)` with `xlabel="Timestep"`, `ylabel="Neuron"`.

**For per-framework activity comparison (manual workflow):**

4. In the **Hardware Deployment Canvas**, run inference on each supported target (snnTorch, Nengo, Rockpool, etc.) separately.
5. For each run, navigate to the **Results** step and export the hidden-layer spike activity via the `.npy` export button in the Dynamics tab.
6. Use an external tool (Python + seaborn, as in the notebook) to compute cosine similarity and generate the heatmap figures. CNLStudio does not replicate this aggregation step.

---

## Missing Features / Recommended CNLStudio Additions

The following features are required to fully support the paper notebooks and are recommended for the product backlog:

### P0 — ✅ Both items shipped (16 June 2026)

**1. ✅ `cnl.RSynaptic` neuron node in Model canvas**
- `snn.RSynaptic`: recurrent synaptic neuron with dual time constants (alpha = synaptic decay, beta = membrane decay), built-in recurrent Linear connection, configurable reset mechanism ("subtract" / "zero").
- Implementation: CNLStudio-internal `cnl.` prefix (not a standard NIR primitive). Serialized via `nir_graph_serializer.py`; dispatched via `snntorch_simulator.py`. Support classification: `snntorch_sim=exact`, `lava_sim=unsupported`. Nengo preview: unsupported (Nengo has no RSynaptic equivalent — canvas preview shows "unsupported" for this node type).
- Parameters: `n_neurons`, `alpha`, `beta`, `threshold`, `reset_mechanism` (subtract/zero), `use_bias`.
- Used in: Braille_training, snntorch_apply_subtract, nengo_apply.

**2. ✅ `cnl.Synaptic` neuron node in Model canvas**
- `snn.Synaptic`: non-recurrent variant with synaptic trace (alpha) + membrane (beta), two hidden states (syn, mem).
- Implementation: same `cnl.` prefix pattern. `snntorch_sim=exact`, `lava_sim=unsupported`.
- Parameters: `n_neurons`, `alpha`, `beta`, `threshold`, `reset_mechanism`.
- Used as the output layer in the Braille RNN (Notebooks 3, 4, 5).

### P1 — ✅ All three shipped (16 June 2026)

**3. ✅ Tonic / event-based dataset integration in Data Loader**
- `tonic.datasets.NMNIST` with `tonic.transforms.ToFrame(time_window=1ms)` is the standard DVS dataset pipeline.
- Implemented: Data Loader node gains `format` dropdown (`auto`/`tonic_nmnist`/`tonic_shd`/`npy`/`pt`/`hdf5`) and `time_window_ms` field. Backend: `DatasetFormat.tonic_nmnist` / `tonic_shd` added to `dataset_loader.py`; lazy `tonic` import with actionable error; `_tonic_loading_code()` in `notebook.py` generates correct `ToFrame` notebook cells.
- Files: `pipeline_dag.dart`, `pipeline_node_property_panel.dart`, `dataset_loader.py`, `notebook.py`.

**4. ✅ L1/L2 spike regularization in Training canvas**
- The Braille training notebook uses both L1 (mean spike count) and L2 (squared total spike count) regularization terms on the hidden layer.
- Implemented: `l1SpikeReg` and `l2SpikeReg` nodes added to Training canvas palette (loss category, `snntorch_sim` only). Property panel: weight + target layer fields. Code-gen emits `loss_val = loss_val + weight * spk.sum()` / `(spk**2).sum()`. Training adapter reads `l1_reg_weight` / `l2_reg_weight` from payload.
- Files: `pipeline_dag.dart`, `pipeline_node_property_panel.dart`, `pipeline_phase_canvas.dart`, `notebook.py`, `snntorch_adapter.py`.

**5. ✅ Surrogate gradient slope parameter**
- `surrogateBackward` node now exposes `function` dropdown (`fast_sigmoid`/`sigmoid`/`atan`/`straight_through_estimator`) and `slope` field (default 25.0). Flat-config path reads `cfg.surrogate_function` + `cfg.surrogate_slope`; no more hardcoded `slope=25`. Training adapter uses `getattr(surrogate, surrogate_fn_name)`.
- Files: `pipeline_dag.dart`, `pipeline_node_property_panel.dart`, `pipeline_phase_canvas.dart`, `notebook.py`, `snntorch_adapter.py`.

### P2 — ✅ All three shipped (16 June 2026)

**6. ✅ NIR file import into Model canvas**
- "Import NIR..." added to the export/file menu (`PopupMenuButton` in `export_menu.dart` and the Export workspace panel). Opens `.nir` file picker → calls `canonicalDocProvider.updateFromNirFile()` + `nirImportProvider.inspectFile()` — same path as the NIR Inspector tab. Notebooks 1 and 2 no longer require manual graph reconstruction.
- Files: `export_menu.dart`.

**7. ✅ Cross-target activity export (.npy) from Results step**
- New endpoint `GET /api/neurosim/simulations/{job_id}/activity.npy`. `?node_id=X&probe=spikes` → single `.npy` (1-D spike times or `(T, N)` voltage). No `node_id` → zip of all probes as `{node_id}_{probe}.npy` files. `_probe_to_ndarray()` converts job result dicts to dense float32 arrays. Exposed in the Results step → Dynamics tab via the export button.
- Files: `neurocnl/neurosim/app/routers/preview.py`.

**8. ✅ Nengo probe/dt configuration**
- `PipelineConfigPayload` gains `nengo_dt=1e-4`, `nengo_presentation_time=1e-4`, `nengo_probes=["spikes"]`. All 3 Nengo notebook cells (train/eval/infer) now use `nengo.Simulator(model, dt=cfg.nengo_dt)` and `sim.run(cfg.nengo_presentation_time)`. Eval/infer cells conditionally add `voltage_probe` when `"voltage" in cfg.nengo_probes`. `nengo_code_exporter.py` accepts `dt`, `presentation_time`, `probes` kwargs; supports spikes/voltage/decoded probe types.
- Files: `notebook.py`, `nengo_code_exporter.py`.

### P3 — ✅ All three shipped (17 June 2026)

**9. ✅ `.pt` PyTorch TensorDataset loader in Data Loader node**
- Data Loader node now natively handles `.pt` files saved as `torch.TensorDataset`, `dict` (`{data, labels}`), or `tuple`. Loaded with `weights_only=True`; tensors converted GPU-safely via `.detach().cpu().numpy()`.
- Set `format=pt` and provide `dataset_path` in the Data Loader property panel — the field is conditionally shown for `pt` and `npy` formats.
- Code-gen produces a working `torch.load` + `DataLoader` cell. Three new pytest tests cover format detection and all three `.pt` shapes.
- Files: `dataset_loader.py`, `notebook.py`, `pipeline_dag.dart`, `pipeline_node_property_panel.dart`.
- Fixes Notebooks 3 and 4: `ds_train.pt`, `ds_val.pt`, `ds_test.pt` now load without external conversion.

**10. ✅ JSON Import Config button in export panel**
- New **Import Config...** button (tune icon) in the Core card of the export/workspace panel. Opens a file picker for `.json` files.
- Parses the JSON into `PipelineConfig` and calls `canvasProvider.notifier.updatePipeline()` — hyperparameters (epochs, learning_rate, optimizer, batch_size, etc.) are applied directly to the active canvas.
- Useful for Notebook 3: load `data/parameters_noDelay_noBias_ref_subtract.json` to set `N_hidden`, `alpha_r`, `beta_r`, `alpha_out`, `beta_out`, `lr`, `slope`, `reg_l1`, `reg_l2` in one step.
- Files: `export_menu.dart`, `pipeline_config.dart`, `canvas_provider.dart`.

**11. ✅ Native Dynamics Visualization & NPY Export (Results step)**
- Implemented the **"Dynamics" tab** in the Results step — this is the consolidated home for all post-run visualization (spike rasters, membrane voltage traces, label probability charts). There is no separate monitoring canvas or monitoring cell; the Training step covers live metrics during training, and the Results step covers everything after a run completes.
- Integrated NPY binary data fetching and parsing for plotting `SnnDynamicsView` and providing `.npy` zip exports.
- Added a `LabelProbabilitiesChart` to support visual inspection of model prediction confidence (Notebook 4).

**12. ✅ Spike Generator canvas node (Shipped after 17 June 2026)**
- Fully implemented: `spikeGenerator` node in Data palette (`pipeline_dag.dart`, `pipeline_node_property_panel.dart`, `pipeline_phase_canvas.dart`, `pipeline_palette.dart`).
- Parameters: `n_neurons`, `n_timesteps`, `pattern` (`isi_regular`/`poisson`/`constant_rate`), `isi_period`, `rate_hz`, `seed` — with pattern-conditional UI.
- Backend code-gen: `_spike_generator_code()` in `notebook.py` emits `_spikes[isi_period-1::isi_period] = 1.0` for `isi_regular`, Poisson sampling for `poisson`, and constant-rate fill for `constant_rate`.
- Fixes Notebook 1.

### P4 — ✅ Both items shipped (post 17 June 2026)

**13. ✅ `ceCountLoss` node in Training canvas**
- `case "ceCountLoss"` added to `_dag_node_code()` in `notebook.py`: generates `SF.ce_count_loss()` from snnTorch's functional module — the correct spike-count cross-entropy used by the Braille notebooks.
- Distinct from `crossEntropyLoss` (which uses `nn.CrossEntropyLoss` on logits). Required by Notebooks 3 and 4.
- **27 June 2026 update:** `ceCountLoss` enum entry, label, category (loss), frameworks (`snntorch_sim`), defaultParameters, inputPorts, and outputPorts added to `pipeline_dag.dart` — the Dart palette entry was missing until now, so the node was never visible in the UI despite the Python codegen being present.

**14. ✅ `cnl.RSynaptic` / `cnl.Synaptic` in `_generate_snntorch_code()`**
- Both node types added to the architecture code generator in `notebook.py`. For graphs containing RSynaptic, a temporal-sequence forward is generated: `for t in range(x.shape[0]): xt = x[t]` with explicit state threading (`init_rsynaptic()` / `init_synaptic()`).
- Hidden-layer spikes (from RSynaptic) returned as the second output (`hid_rec`) so L1/L2 reg can reference `mem_out` as the target layer.
- Fixes Notebooks 3 and 4.

### P5 — ✅ All 10 shipped (27 June 2026)

#### Model canvas additions (4 new neuron/layer types)

**15. ✅ `cnl.RLeaky` — Recurrent LIF neuron**
- `snn.RLeaky(beta, linear_features, threshold, reset_mechanism)` with two states `(spk, mem)` from `init_rleaky()`. Built-in internal recurrent `nn.Linear(n, n)` for spike-feedback — simpler than RSynaptic (2 states vs 3).
- Code-gen: temporal loop (`for t in range(x.shape[0])`) triggered by `kind="rleaky"` in `_recurrent_kinds`; forward call `self.rleaky(xt, spk, mem)` → `(spk, mem)`.
- Files: `cnl_nodes.py` (dataclass), `nir_graph_serializer.py` (spec + serialize/deserialize), `nir_support.py` (`snntorch_sim=exact`, others `unsupported`), `nir_types_provider.dart` (palette entry, category=neuron, icon=Icons.loop), `notebook.py` (isinstance branch).

**16. ✅ `cnl.Leaky` — Explicit-beta Leaky neuron**
- `snn.Leaky(beta, threshold, reset_mechanism, init_hidden=False)` with one state `mem` from `init_leaky()`. Lets users specify decay as `beta` directly instead of converting from tau (as `nir.LIF` requires).
- Code-gen: same temporal loop path (`kind="leaky_explicit"`); forward call `self.lk(xt, mem)` → `(spk, mem)`.
- Files: same 5-file pattern as RLeaky. `nir_types_provider.dart` category=neuron, icon=Icons.hub.

**17. ✅ `cnl.BatchNorm1d` — Batch normalisation layer**
- `nn.BatchNorm1d(num_features)` — stateless; no `spiking_vars` entry, no state init. Forward: `xt = self.bn(xt)` inside the temporal loop.
- Files: same 5-file pattern. `nir_support.py` all backends `exact` (pure PyTorch). `nir_types_provider.dart` category=transform, icon=Icons.auto_fix_normal, single param `num_features`.

**18. ✅ `cnl.Dropout` — Dropout layer**
- `nn.Dropout(p)` — stateless. Forward: `xt = self.drop(xt)`.
- Files: same 5-file pattern. `nir_types_provider.dart` category=transform, icon=Icons.blur_on, single param `p` (float, 0–1).

#### Pipeline canvas additions (6 new training/eval utility nodes)

**19. ✅ `gradientClip` — Gradient norm clipping**
- `torch.nn.utils.clip_grad_norm_(net.parameters(), max_norm=<max_norm>)`. Category: backward. Frameworks: `snntorch_sim` only.
- Property panel: single `max_norm` double field (default 1.0). Input port: `gradients`.
- Files: `pipeline_dag.dart`, `pipeline_node_property_panel.dart`, `notebook.py`.

**20. ✅ `weightClip` — Hard weight clipping**
- `with torch.no_grad(): for _wp in net.parameters(): _wp.clamp_(<min>, <max>)`. Category: optimiser.
- Property panel: `min_weight` + `max_weight` double fields. Input port: `model`.
- Files: same 3-file pattern.

**21. ✅ `reduceLROnPlateau` — Adaptive LR scheduler**
- `torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode, factor, patience, min_lr)`. Category: scheduler. Frameworks: all (framework-agnostic PyTorch).
- Code-gen comment instructs caller: `# Call scheduler.step(val_loss) at end of each epoch`.
- Property panel: `factor` (double), `patience` (int), `min_lr` (double). Input port: `model`.
- Files: same 3-file pattern.

**22. ✅ `earlyStopping` — Epoch-level early stopping**
- Emits sentinel variables `_es_best`, `_es_counter`, `_es_patience`, `_es_min_delta` and a commented epoch-loop footer with `break` logic. Category: scheduler. Frameworks: all.
- Property panel: `patience` (int) + `min_delta` (double). Input port: `model`.
- Files: same 3-file pattern.

**23. ✅ `spikeCountMetric` — Mean output spike count**
- `mean_spike_count = spk_out.sum(0).float().mean().item()` — reports average spikes per output neuron per sample. No parameters. Category: metrics. Frameworks: `snntorch_sim` only.
- Input ports: `spikes` + `labels`.
- Files: same 3-file pattern.

**24. ✅ `latencyMetric` — Time-to-first-spike (TTFS) accuracy**
- Full TTFS classification: `argmax(0)` for first spike time, `argmin(1)` for predicted class, no-spike sentinel handling. Category: metrics. Frameworks: `snntorch_sim` only.
- Property panel: `default_latency` int field (sentinel value for non-firing neurons, default −1).
- Input ports: `spikes` + `labels`.
- Files: same 3-file pattern.

---

*Generated from analysis of paper notebooks and CNLStudio source exploration. Canvas capability data sourced from `neurocnl/frontend/lib/providers/canvas/nir_types_provider.dart`, `pipeline_dag.dart`, `pipeline_config.dart`, `deploy_target_catalog.dart`, and `neurocnl/neurocnl/ir/types.py`.*
