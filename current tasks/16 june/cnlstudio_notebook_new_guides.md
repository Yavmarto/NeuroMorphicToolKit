# CNLStudio Notebook Guides — Supplement

**Date:** 4 July 2026
**Relationship to other docs:** This file supplements [cnlstudio_notebook_analysis_extended.md](cnlstudio_notebook_analysis_extended.md). It does not replace anything there. It adds:

- **4 new full "UI Replication Guides"** for notebooks the extended doc rated 🟢 HIGH/buildable or 🟡 MODERATE but never wrote steps for: `lif_norse.ipynb`, `lif_rockpool.ipynb`, `lif_nengo.ipynb`, `lif_sinabs.ipynb`.
- **2 verdict corrections**, downgrading `02_cnn/nengo.ipynb` and `03_rnn/rockpool_apply.ipynb` from 🟡 MODERATE to 🔴 BLOCKED, based on real per-node support tables found in `neurocnl/neurocnl/runtime/nir_support.py` that the extended doc's authors did not have access to when it was written.
- **1 discrepancy note** on `02_cnn/snntorch_sim_fixed.ipynb`, which does not exist in the repo.

All node/parameter names below were verified directly against the current CNLStudio codebase (`neurocnl/frontend/lib/providers/canvas/nir_types_provider.dart`, `pipeline_dag.dart`, `pipeline_node_property_panel.dart`) rather than assumed from the source Python notebooks. Two corrections to the extended doc's assumptions, load-bearing for every guide below:

- CNLStudio's **LIF** node parameters are `tau`, `threshold`, `r`, `v_leak` — not `tau_mem_inv`/`v_th`. Convert with `tau = 1 / tau_mem_inv`, `threshold = v_th`.
- CNLStudio's **Linear**/**Affine** nodes take `rows`, `cols`, `weight_fill` (a single scalar fill value applied uniformly — not a full weight-matrix editor, and no bias field in the UI even for Affine).

---

## `01_lif/lif_norse.ipynb` — new full guide

Supplements the extended doc's row (🟢 HIGH). The extended doc only describes this notebook in prose ("straightforward combination of two already-shipped features"); here are the actual steps.

**Architecture** (from the notebook, `paper/01_lif/lif_norse.ipynb`): `Linear(1×1, bias=False, weight=1) → LIFBoxCell(tau_mem_inv=400, v_th=0.1, dt=0.0001)`, driven by a hand-built 1000-step binary spike train (`d0`, 100 values each expanded 10× with zero-padding).

**Stimulus caveat:** CNLStudio's **Spike Generator** node only supports parametric patterns (`isi_regular`, `poisson`, `constant_rate`) — it cannot reproduce an arbitrary hand-picked bit sequence like `d0`. Workaround (same pattern already used for the Braille dataset in the companion doc's Notebook 3/4 guides, `paper/03_rnn/data/*.pt`): save the expanded `d` tensor to a `.pt` file and load it via a **Data Loader** node instead.

**Step 0 — produce the stimulus file** (one-time setup, outside CNLStudio; this file does not pre-exist in the repo):

```python
import torch

d0 = [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
d = []
for t in d0:
    d.append(t)
    for i in range(9):
        d.append(0)
d = torch.tensor(d).unsqueeze(1).float()  # shape (1000, 1)

torch.save(d, "paper/01_lif/data/lif_stimulus_d.pt")  # create paper/01_lif/data/ first if missing
```

This is copied verbatim from `lif_norse.ipynb` cell 1 (`d0`→`d` construction) with one line appended to persist it.

### UI Replication Guide

**Canvas: Model**

1. Open the **Model** canvas.
2. Add an **Input** node: `n_neurons=1`.
3. Add a **Linear** node: `rows=1`, `cols=1`, `weight_fill=1`.
4. Add a **LIF** node: `n_neurons=1`, `tau=0.0025` (=`1/400`), `threshold=0.1`, `r=1` (default), `v_leak=0` (default).
5. Add an **Output** node: `n_neurons=1`.
6. Connect: **Input → Linear → LIF → Output**.

**Canvas: Eval**

7. Add a **Data Loader** node: `format=pt`, `dataset_path=paper/01_lif/data/lif_stimulus_d.pt`, `batch_size=1`, `shuffle=false`.
8. Add a **State Reset** node. Leave its own `model` input port unconnected — this is intentional, not a gap: CNLStudio compiles one implicit model per project from the Model canvas, and both State Reset and Forward Pass operate on that single compiled model regardless of DAG wiring. The only real (codegen-relevant) edge involving State Reset is its `model` *output* into Forward Pass below.
9. Add a **Forward Pass** node: `eval_mode=true`.
10. Connect the node ports as follows:
    - **Data Loader** (`data`) → **Forward Pass** (`input`)
    - **State Reset** (`model` out) → **Forward Pass** (`model` in)
    *(Note: remaining output ports such as `membrane` on the Forward Pass node should be left unconnected — there's no Accuracy node here since this notebook has no labels, only a raw spike/voltage trace.)*
11. Click **Run Eval**.

**Canvas: Train** (Export)

12. Add a **NIR Exporter** node: `filename=lif_norse.nir`.
13. Connect **Forward Pass** (`model` out) → **NIR Exporter** (`model` in). (This notebook has no training loop — it's a pure forward pass over the fixed stimulus — so this is the *built* model, not a *trained* one.)

**Results Step: Dynamics Tab**

14. Navigate to the **Results** step and open the **Dynamics** tab. Select the **LIF** node — the Membrane Voltage Trace panel and Spike Raster panel reproduce the notebook's `lif_trace_norse.png` plot.

---

## `01_lif/lif_rockpool.ipynb` — correction note + guide

**Correction:** the extended doc's table lists this as "LIF inference on Rockpool" (implying deployment to a Rockpool target). Direct inspection of `paper/01_lif/lif_rockpool.ipynb` shows it does not import any NIR file — it builds a fresh model directly in Rockpool (`LinearTorch` + `LIFNeuronTorch`) and *exports* NIR via `rockpool.nn.modules.to_nir()`. This is the same **model-authoring** role as `lif_norse.ipynb`, just authored in a different source framework — not a deploy-to-Rockpool-target scenario. (A genuine "deploy to Rockpool" workflow is separately covered by the guide below for `lif_nengo.ipynb`/`lif_sinabs.ipynb` — this architecture, being pure `Linear`+`LIF` with no `Affine`, would in fact also be supported by Rockpool's real codegen target since `Linear` is exact and `LIF` is approximate there, but that's a distinct exercise from what this notebook does.)

### UI Replication Guide

Identical to the `lif_norse.ipynb` guide above, with one parameter change: in step 3, use `weight_fill=0.04` instead of `1` (confirmed from the notebook's `c[0].weight.data.fill_(.04)`). Export filename: `lif_rockpool.nir`.

---

## `01_lif/lif_nengo.ipynb` — new full guide

Supplements the extended doc's 🟡 MODERATE row. Real support check: `neurocnl/neurocnl/runtime/nir_support.py:318-323` — for the `nengo` backend, `Linear` is `"exact"`, `LIF` is `"approximate"` but only if `r==1` and `v_leak==0` (raises otherwise). Both hold here since they're the LIF node's defaults — this notebook's architecture is fully supported (approximate tier, not blocked).

### UI Replication Guide

**Canvas: Model**

1. Build the model exactly as in `lif_norse.ipynb`'s guide, steps 1–6 (`Input → Linear(weight_fill=1) → LIF(tau=0.0025, threshold=0.1, r=1, v_leak=0) → Output`).

**Canvas: Eval**

2. Same Data Loader / State Reset / Forward Pass steps as `lif_norse.ipynb`'s guide, steps 7–11, including the `paper/01_lif/data/lif_stimulus_d.pt` stimulus file from that guide's Step 0 (same stimulus workaround applies — Nengo simulation timing in the notebook uses `dt=1e-4`, `presentation_time=dt`, matching the same spike train).

No **NIR Exporter** step is needed here: CNLStudio's Deploy step compiles NIR directly from the live model spec on every preview/deploy action (`compile_to_nir(request.spec)`) and never depends on a NIR Exporter node having run. NIR Exporter is a separate, optional convenience for persisting a `.nir` file to disk for other tools — omitting it below is correct, not an oversight.

**Deploy**

3. Open the **Deploy** step. In the Deploy Target catalog, select **Nengo** (`id: nengo`).
4. The codegen preview will show an amber **"Approximate"** badge (not "Fully supported") — this is expected and matches the `LIF` node's real classification for this backend, not an error.
5. In the **Setup** step, select **Nengo** as a target platform.
6. In the **Notebook** step, generate the notebook for the Nengo target (`POST /api/notebook/generate-v2`) and open it in the embedded Jupyter Lab. The generated code round-trips the model through `nengo_io.py`'s converter, equivalent to the notebook's `nir_to_nengo()`.

---

## `01_lif/lif_sinabs.ipynb` — new full guide

Supplements the extended doc's 🟡 MODERATE row. Real support check: `neurocnl/neurocnl/converter/sinabs_io.py:262` — `_SUPPORTED = (nir.Linear, nir.Affine, nir.LIF, nir.IF)`. `Linear`/`Affine` are exact; `LIF`/`IF` are approximate (only `tau` is read — `threshold`/`v_leak`/`r` are dropped to sinabs defaults, per `sinabs_io.py:296-297`). This architecture (`Linear`+`LIF`) is fully supported at the approximate tier.

### UI Replication Guide

**Canvas: Model**

1. Build the model exactly as in `lif_norse.ipynb`'s guide, steps 1–6.

**Canvas: Eval**

2. Same Data Loader / State Reset / Forward Pass steps as `lif_norse.ipynb`'s guide, steps 7–11, including the `paper/01_lif/data/lif_stimulus_d.pt` stimulus file from that guide's Step 0.

No **NIR Exporter** step is needed here, same reasoning as the Nengo guide above: Deploy compiles NIR directly from the live model spec, independent of whether a NIR Exporter node ran.

**Deploy**

3. Open the **Deploy** step. In the Deploy Target catalog, select **Sinabs** (`id: sinabs`).
4. The codegen preview will show an amber **"Approximate"** badge — expected, since only `tau` survives the conversion (matching the notebook's own `lif_layer.tau_mem.data /= dt` rescale step; `threshold`/`v_leak`/`r` are silently reset to sinabs defaults, so exact numeric parity with the notebook's `v_th=0.1` should not be expected). `sinabs_io.py:295` constructs the sinabs layer as `sl.LIF(tau_mem=...)` with no other arguments, so whatever the installed `sinabs` package's own `LIF` constructor defaults to (e.g. its own default `v_threshold`) is what applies — this is an external-dependency default, not a CNLStudio or repo-internal value, so check it against your installed `sinabs` version rather than assuming a number.
5. In the **Setup** step, select **Sinabs** as a target platform, then generate/open the notebook via the **Notebook** step, same flow as the Nengo guide above.

---

## `02_cnn/nengo.ipynb` — verdict correction: 🟡 MODERATE → 🔴 BLOCKED

The extended doc's stated blocker was "no formal per-node support table" for Nengo. That's incorrect — a real table exists at `neurocnl/neurocnl/runtime/nir_support.py:315-340`, and it formally blocks this notebook:

```
"Conv2d": "unsupported",
"Flatten": "unsupported",
"IF": "unsupported",
"SumPool2d": "unsupported",
```

This CNN architecture (`Input → Conv2d → LIF → Conv2d → LIF → AvgPool2d → Conv2d → LIF → AvgPool2d → Flatten → Linear → LIF → Linear → LIF → Output`) requires `Conv2d`, `Flatten`, and (per the notebook's custom `nengo_import.py`, which also handles `SumPool2d`) potentially `SumPool2d` — all four unsupported node types this table blocks are load-bearing for this graph. CNLStudio's Nengo codegen target will show a red "Unsupported" badge and block/flag the run; no UI workaround exists short of rewriting the architecture without convolutions, which isn't this notebook. No guide is possible until a converter update ships support for these node types.

---

## `03_rnn/rockpool_apply.ipynb` — verdict correction: 🟡 MODERATE → 🔴 BLOCKED

The extended doc flagged this as "unverified whether `rockpool_io` has been extended" to handle `cnl.RSynaptic`/`cnl.Synaptic`. It has been verified now, and it has not: `neurocnl/neurocnl/converter/rockpool_io.py:98-172`'s `from_nir()` only branches on `nir.Linear`, `nir.LIF`, `nir.CubaLIF` — anything else, including `cnl.Synaptic`/`cnl.RSynaptic`, falls through to the trailing `else: raise ValueError(...)` at line 170. This matches the formal table in `nir_support.py`, which marks both `Synaptic` and `RSynaptic` `"unsupported"` for the `rockpool` backend. The Braille RNN graph this notebook loads uses both node types throughout — CNLStudio's Rockpool codegen target will reject it outright. No guide is possible until a converter update ships support for these two node types.

---

## `02_cnn/snntorch_sim_fixed.ipynb` — discrepancy note

This file does not exist anywhere in the repository — confirmed via `find paper -iname "*sim_fixed*"` (no matches) and a full `git log --all --diff-filter=A` search (never added in any commit, on any branch). The closest match in `paper/02_cnn/` is `snntorch_apply.ipynb`, which already has a full guide in the companion doc (`cnlstudio_notebook_analysis.md`, Notebook 2).

The bug this phantom notebook was said to fix — `tonic.collation.PadTensors` defaulting to `batch_first=True` — cannot occur in CNLStudio regardless of which notebook is used as reference: `backend/app/routers/notebook.py:1397` hardcodes `PadTensors(batch_first=False)` in all generated code for `tonic_*`-format Data Loaders. It is not a user-configurable UI parameter, so there is no equivalent "unfixed" state to guide around in CNLStudio's workflow.
