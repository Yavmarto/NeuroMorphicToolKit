# CNLStudio Notebook Reverse-Engineering Analysis — Extended (Remaining 36 Notebooks)

**Date:** 2 July 2026
**Scope:** All notebooks under `paper/` NOT covered by the original report — 36 of the 42 total `.ipynb` files in `paper/01_lif`, `paper/02_cnn`, `paper/03_rnn`, and `paper/figures` (confirmed via `find paper -iname "*.ipynb"`).
**Companion document:** [cnlstudio_notebook_analysis.md](cnlstudio_notebook_analysis.md) — covers the first 6 notebooks (`01_lif/lif_snntorch.ipynb`, `02_cnn/snntorch_apply.ipynb`, `03_rnn/Braille_training_snntorch.ipynb`, `03_rnn/snntorch_apply_subtract.ipynb`, `03_rnn/nengo_apply.ipynb`, `03_rnn/plots.ipynb`) and the current CNLStudio node-palette history (P0–P5 shipped features through 27 June 2026).

## Why these 36 exist

`paper/01_lif`, `02_cnn`, and `03_rnn` each represent one architecture (single LIF neuron, CNN on N-MNIST, recurrent SNN on Braille tactile data). Each task exports **one canonical NIR graph** from a source framework (Norse for LIF, Sinabs for CNN, snnTorch for RNN) and then runs that same graph on every supported simulator/hardware platform — confirmed directly from the per-folder READMEs. The 36 notebooks below are that per-platform fan-out, plus comparison/debug/reference notebooks that aren't buildable workflows at all.

## Support matrix used for verdicts (read from source, 2 July 2026)

CNLStudio's `nir_support.py` gives a **formal, per-node exact/approximate/unsupported classification** for only three deploy targets:

| Target | Exact | Approximate | Unsupported (relevant here) |
|---|---|---|---|
| `snntorch_sim` | Input, Output, Linear, Affine, Conv2d, Flatten, IF, LIF, AvgPool2d, Synaptic, RSynaptic, RLeaky, Leaky, BatchNorm1d, Dropout | CubaLIF, Delay | LI, I, SumPool2d, Scale |
| `lava_sim` | Input, Output, Linear, LIF | CubaLIF, Delay | **Affine, Conv2d, everything `cnl.*`** |
| `sc_neurocore_sim` (custom PYNQ‑Z2/FPGA target — unrelated to SpiNNaker2, confirmed via `docs/Hardware Validation Plan_ PYNQ-Z2 and BrainChip AKida.md`) | Input, Output, Linear, Affine, IF, LIF | CubaLIF, Delay | Conv2d, everything `cnl.*` |

Six more targets exist in the deploy catalog with real backend converters (`brian2_io`, `sinabs_io`, `rockpool_io`, `pynn_io`, `nengo_io`, `akida_mapper`) but **no formal per-node table** — same situation the original report already flagged for `nengo_apply.ipynb` (custom `nir_to_nengo` converter, rated 🟡 MODERATE). These get the same treatment here.

**No CNLStudio deploy target exists at all** for SpiNNaker2, Spyx, Xylo, or Norse (verified by grep across `neurocnl/` — zero converter/backend code). Norse is only ever used in these papers as the *authoring* framework for the LIF task's reference graph, never as something CNLStudio itself runs.

## Summary Table

| Notebook | Purpose | Target | Viability | Primary Blocker |
|---|---|---|---|---|
| `01_lif/lif_norse.ipynb` | Hand-author LIF model + export NIR | *(N/A — model authoring)* | 🟢 HIGH | None — buildable via Model canvas + NIR Exporter |
| `01_lif/lif_lava.ipynb` | LIF inference on Lava | Lava (`lava_sim`) | 🔴 LOW | `Affine` unsupported at `lava_sim` |
| `01_lif/lif_nengo.ipynb` | LIF inference on Nengo | Nengo | 🟡 MODERATE | No per-node support table for Nengo |
| `01_lif/lif_rockpool.ipynb` | LIF inference on Rockpool | Rockpool | 🟡 MODERATE | No per-node support table for Rockpool |
| `01_lif/lif_sinabs.ipynb` | LIF inference on Sinabs | Sinabs | 🟡 MODERATE | No per-node support table for Sinabs |
| `01_lif/lif_spyx.ipynb` | LIF inference on Spyx | Spyx | 🔴 LOW/BLOCKED | No Spyx deploy target exists |
| `01_lif/debug_spike_representation/Run on SpiNNaker2.ipynb` | LIF inference on SpiNNaker2 | SpiNNaker2 | 🔴 LOW/BLOCKED | No SpiNNaker2 deploy target exists |
| `01_lif/lif_exact_sim.ipynb` | Analytical LIF reference | *(none)* | ⬜ N/A | Not a workflow — closed-form math reference |
| `01_lif/lif_comparison.ipynb` | Cross-platform comparison plot | *(none)* | ⬜ N/A | Not a workflow — aggregates external CSVs |
| `02_cnn/snntorch_sim_fixed.ipynb` | CNN inference on snnTorch (bugfixed) | snnTorch | 🟢 HIGH | None — same as analyzed Notebook 2 |
| `02_cnn/lava_apply.ipynb` | CNN inference on Lava | Lava (`lava_sim`) | 🔴 LOW | `Conv2d` unsupported at `lava_sim` |
| `02_cnn/nengo.ipynb` | CNN inference on Nengo | Nengo | 🟡 MODERATE | No per-node support table for Nengo |
| `02_cnn/norse_apply.ipynb` | CNN inference on Norse | Norse | 🔴 LOW/BLOCKED | No Norse deploy target exists |
| `02_cnn/s2_apply.ipynb` | CNN inference on SpiNNaker2 | SpiNNaker2 | 🔴 LOW/BLOCKED | No SpiNNaker2 deploy target exists |
| `02_cnn/spyx.ipynb` | CNN inference on Spyx | Spyx | 🔴 LOW/BLOCKED | No Spyx deploy target exists |
| `02_cnn/cnn_numbers.ipynb` | Generate `cnn_numbers.npy` test fixture | *(none)* | ⬜ N/A | Data-prep utility, not a model workflow |
| `02_cnn/gen_snn.ipynb` | Unclear/dev scratch pipeline scaffold | snnTorch (partial) | ⬜ N/A | Appears to be a tool-generated dev artifact, dataset wiring stubbed out |
| `02_cnn/cnn_plots.ipynb` | Paper comparison plots/table | *(none)* | ⬜ N/A | Not a workflow — aggregates external results |
| `02_cnn/archive/cnn_comparison.ipynb` | Archived comparison notebook | *(none)* | ⬜ N/A | Superseded/archived |
| `02_cnn/ann_pretraining/*.ipynb` (2 notebooks) | ANN pretraining pipeline for the base CNN | *(none)* | ⬜ N/A | Out of scope — ANN training precedes CNLStudio's SNN canvas entirely |
| `03_rnn/snntorch_apply_zero.ipynb` | RNN inference, `reset_mechanism="zero"` | snnTorch | 🟢 HIGH | None — new full guide below |
| `03_rnn/rockpool_apply.ipynb` | RNN inference on Rockpool | Rockpool | 🟡 MODERATE | `rockpool_io` must handle `cnl.RSynaptic`/`cnl.Synaptic` (custom ops, unverified) |
| `03_rnn/norse_apply.ipynb` | RNN inference on Norse | Norse | 🔴 LOW/BLOCKED | No Norse deploy target exists |
| `03_rnn/spyx_apply.ipynb` | RNN inference on Spyx | Spyx | 🔴 LOW/BLOCKED | No Spyx deploy target exists |
| `03_rnn/xylo_apply.ipynb` | RNN inference on Xylo | Xylo | 🔴 LOW/BLOCKED | No Xylo deploy target exists |
| `03_rnn/extras/*.ipynb` (8 notebooks) | Dev/debug drafts preceding the polished root notebooks | mixed | ⬜ N/A | Superseded drafts / one-off debug scripts, not distinct workflows |
| `figures/figures.ipynb` | Master paper figure generator | *(none)* | ⬜ N/A | Not a workflow — publication figures |
| `figures/NIR_explainer/nir_explainer.ipynb` | NIR format tutorial/explainer | *(none)* | ⬜ N/A | Not a workflow — documentation notebook |

---

## `paper/01_lif/` (9 notebooks)

### `lif_norse.ipynb` — 🟢 HIGH
Hand-builds `Input → Linear(1×1, no bias) → LIF (tau_mem_inv=400, v_th=0.1)` in Norse, drives it with a hardcoded spike train, and calls `norse.torch.to_nir()` + `nir.write()` to produce `lif_norse.nir` — the exact file `lif_snntorch.ipynb` (already analyzed) imports. No dataset, no training loop: this is model *authoring*, not simulation on Norse.

This is the reverse direction of the already-analyzed Notebook 1: instead of **importing** a NIR file, the user **builds** the same graph by hand in the Model canvas (`Input → Affine/Linear → LIF → Output`, same node types already confirmed available) and then uses the existing **NIR Exporter** in Hardware Deployment (already shipped and used in the original report's Notebook 3, step 29) to produce an equivalent `.nir` file. No new node types or converter needed — this is a straightforward combination of two already-shipped features. No new UI guide required beyond referencing those two existing steps.

### `lif_lava.ipynb` — 🔴 LOW
Runs the same `Input → Affine → LIF → Output` graph on Lava. `nir_support.py`'s `lava_sim` table marks `Affine` **unsupported** (only `Linear` is exact) — even though this is the simplest possible architecture, CNLStudio's own native Lava simulator classification blocks it at the `Affine` node. `paper/nir_to_lava.py`'s `import_from_nir_to_lava()` does handle `Affine → lava.proc.Dense` mapping, so a workaround exists outside CNLStudio's formal support table — same pattern the original report used for Nengo's custom converter, just here the target is CNLStudio's own built-in Lava simulator rather than an external one.

### `lif_nengo.ipynb`, `lif_rockpool.ipynb`, `lif_sinabs.ipynb` — 🟡 MODERATE (each)
All three run the identical simple `Affine → LIF` graph on their respective platform. Real backend converters exist (`nengo_io`, `rockpool_io`, `sinabs_io`) but none have a formal per-node exact/unsupported classification the way `snntorch_sim`/`lava_sim`/`sc_neurocore_sim` do. Risk is lower than the Braille RNN case (no custom `cnl.*` op involved, just `Affine`+`LIF`), but unverified is unverified — flagged MODERATE per the same rule applied to `nengo_apply.ipynb` in the original report.

### `lif_spyx.ipynb`, `debug_spike_representation/Run on SpiNNaker2.ipynb` — 🔴 LOW/BLOCKED (each)
No Spyx or SpiNNaker2 deploy target exists anywhere in `neurocnl/` — confirmed by grep, not merely absent from the catalog UI. These notebooks cannot be replicated until a new backend/converter is built for either platform; this is a backlog item, not a missing node.

### `lif_exact_sim.ipynb`, `lif_comparison.ipynb` — ⬜ N/A
The former is a closed-form analytical solution to the LIF ODE (no NIR, no simulator) used as a ground-truth reference. The latter loads every platform's `.csv` trace and produces `figures/lif_comparison.pdf`. Neither is a model/training/inference workflow — same rationale as `plots.ipynb` in the original report.

---

## `paper/02_cnn/` (12 notebooks)

### `snntorch_sim_fixed.ipynb` — 🟢 HIGH
Same workflow as the already-analyzed `snntorch_apply.ipynb` (load `cnn_sinabs.nir` via NIR import, evaluate on N-MNIST via `tonic`), with one documented bugfix: the original notebook's `tonic.collation.PadTensors` collate function defaults to `batch_first=True`, which silently produces a batch/time-axis mismatch against the model's expected `(T, B, ...)` layout; the fixed notebook explicitly sets `batch_first=False`. It also drops a redundant hand-built `Net` class in favor of loading purely from the NIR graph. No new node types are needed — this maps to the exact same UI Replication Guide as the original Notebook 2. One thing worth verifying in CNLStudio's own `tonic_nmnist` Data Loader: that its internal collate handling doesn't have the same `batch_first` pitfall, since the source project hit this bug in production.

### `lava_apply.ipynb` — 🔴 LOW
CNN architecture requires `Conv2d`, which `nir_support.py` marks unsupported for `lava_sim`. `nir_to_lava.py`'s `import_from_nir_to_lava_dl()` provides a separate, more capable path mapping `Conv2d`/`SumPool2d`/`CubaLIF` to `lava.lib.dl.slayer` blocks — but that's an external script, not something CNLStudio's own Lava deploy target currently exposes.

### `nengo.ipynb` — 🟡 MODERATE
Same caveat as the LIF/Nengo case: `nengo_io` converter exists, no formal per-node table to confirm `Conv2d`+`LIF` stack coverage.

### `norse_apply.ipynb`, `s2_apply.ipynb`, `spyx.ipynb` — 🔴 LOW/BLOCKED (each)
Norse, SpiNNaker2, and Spyx are not implemented as CNLStudio deploy targets at all.

### `cnn_numbers.ipynb` — ⬜ N/A
Confirmed: loads N-MNIST via `tonic`, takes the first 300 timesteps of one sample per digit class, and saves `cnn_numbers.npy` (shape `(300,10,2,34,34)`, matching `02_cnn/README.md`). Pure data-fixture generation — CNLStudio's `tonic_nmnist` Data Loader format already loads N-MNIST directly, making this manual fixture-prep step unnecessary in CNLStudio's workflow.

### `gen_snn.ipynb` — ⬜ N/A
Despite the name suggesting an ANN→SNN conversion notebook (which the README attributes to `sinabs.py`, not this file), this is an auto-generated NMTK pipeline scaffold (banner "Generated ... UTC", `_nmtk_emit` progress hooks, dataset wiring left as stub comments) that compiles a CNL spec to NIR and rebuilds it in snnTorch from an external `weights.npz`. It looks like tool output/dev scratch rather than an intended paper artifact, and has no clean output to replicate.

### `cnn_plots.ipynb`, `archive/cnn_comparison.ipynb` — ⬜ N/A
Publication comparison plots/table generation and an archived, superseded predecessor — not workflows.

### `ann_pretraining/test-converted-snn.ipynb`, `ann_pretraining/test_data.ipynb` — ⬜ N/A
Part of the ANN pretraining pipeline (`cnn.py`, `train.py`, Lightning checkpoints) that produces the base ANN *before* `sinabs.py` converts it to an SNN and exports NIR. This precedes CNLStudio's scope entirely — CNLStudio's Model canvas starts from an SNN/NIR graph, not an ANN training pipeline.

---

## `paper/03_rnn/` (13 notebooks)

### `snntorch_apply_zero.ipynb` — 🟢 HIGH (new guide below)
Same RNN architecture as the already-analyzed Notebook 4, but with `reset_mechanism="zero"` **and** bias enabled (`braille_noDelay_bias_zero.nir` / `model_noDelay_bias_ref_zero.pt` / `parameters_noDelay_bias_ref_zero.json` — confirmed present in `paper/03_rnn/data/`), versus the "subtract" variant's no-bias configuration. `cnl.RSynaptic`/`cnl.Synaptic` already support both `reset_mechanism` values and a `use_bias` flag (shipped in the P0 features), so this is fully buildable today. Because the bias/reset combination differs from the original guide, it gets its own short replication guide:

**UI Replication Guide — `snntorch_apply_zero.ipynb`**

*Canvas: Model* — Build as in the original Notebook 3 guide, steps 1–8, with two changes: enable bias on both **Linear** nodes (`use_bias=true`), and set **cnl.RSynaptic** / **cnl.Synaptic** `reset_mechanism="zero"`, `use_bias=true`.

*Canvas: Hardware Deployment* — Load the pre-trained weights from `data/model_noDelay_bias_ref_zero.pt` (or, if trained in CNLStudio, load the saved checkpoint).

*Canvas: Eval* — Add a **Data Loader** (`format=pt`, `dataset_path=paper/03_rnn/data/ds_test.pt`, `batch_size=64`), **State Reset**, **Forward Pass** (`eval_mode=true`), and **Accuracy** nodes, wired identically to the original Notebook 4 guide. Click **Run Eval**.

*Results Step* — Same Dynamics tab / label-probability panel as Notebook 4.

### `rockpool_apply.ipynb` — 🟡 MODERATE
Loads a Braille NIR graph containing `cnl.RSynaptic`/`cnl.Synaptic` — CNLStudio-internal node types, not standard NIR primitives — into Rockpool via `rockpool_io`. This is the same class of risk the original report already called out for `nengo_apply.ipynb`'s custom `nir_to_nengo` converter: it's unverified whether `rockpool_io` has been extended to serialize/deserialize these custom ops. Flagged MODERATE with this specific blocker rather than the generic "no per-node table" caveat.

### `norse_apply.ipynb`, `spyx_apply.ipynb`, `xylo_apply.ipynb` — 🔴 LOW/BLOCKED (each)
No Norse, Spyx, or Xylo deploy target exists in CNLStudio.

### `extras/` (8 notebooks) — ⬜ N/A
All confirmed (by reading each) to be development drafts or one-off debug scripts that precede and are superseded by the four polished root notebooks:

| Notebook | Superseded by / nature |
|---|---|
| `2311_norse_snntorch.ipynb` | Manual Norse/snnTorch param cross-check — draft, superseded by `norse_apply.ipynb` |
| `Subgraph_rnn.ipynb` | NIR subgraph construction scratch work — no root counterpart |
| `lava_analysis_simple.ipynb` | Manual snnTorch-vs-Lava-DL neuron parity check — no root counterpart (Lava isn't one of the 4 polished RNN notebooks) |
| `rockpool_inference.ipynb` | Early draft — superseded by `rockpool_apply.ipynb` |
| `"snnTorch inference.ipynb"` | Incomplete/exploratory — superseded by `snntorch_apply_zero.ipynb` |
| `"snnTorch save data.ipynb"` | Dev data-prep script — superseded by root notebooks' built-in save logic |
| `"snntorch save subtract.ipynb"` | Earlier iteration, hardcoded reset path — superseded by `snntorch_apply_subtract.ipynb` |
| `snntorch_debug_nirgraphs.ipynb` | Pure NIR-graph diff/equality debug utility — not a workflow at all |

None represent a distinct, undocumented workflow; they add no new information beyond what the 6+2 already-analyzed/newly-rated root notebooks cover.

---

## `paper/figures/` (2 notebooks)

### `figures.ipynb`, `NIR_explainer/nir_explainer.ipynb` — ⬜ N/A
`figures.ipynb` is the master generator for the paper's publication PDFs (all files under `paper/figures/*.pdf`). `nir_explainer.ipynb` is a standalone tutorial explaining the NIR format itself (Linear/LIF/LI primitive visualizations). Neither is a model training/inference workflow — same "by design, out of scope" rationale as `plots.ipynb` in the original report.

---

## Missing Features / Recommended CNLStudio Additions (new items from this pass)

The original report's P0–P5 backlog items are all shipped. This pass surfaces genuinely new gaps:

**1. No deploy target for SpiNNaker2, Spyx, or Xylo.** Six notebooks (`lif_spyx.ipynb`, the SpiNNaker2 debug notebook, `s2_apply.ipynb`, `spyx.ipynb`, `spyx_apply.ipynb`, `xylo_apply.ipynb`) target these platforms and are entirely blocked until a converter/backend is built for each — this is new backend work, not a node-palette gap. Note `sc_neurocore_sim`/`sc_neurocore_fpga` are a *different*, already-implemented custom PYNQ-Z2/FPGA target unrelated to SpiNNaker2; don't conflate the two.

**2. No formal per-node support classification for the 6 "converter exists but unclassified" targets** (`nengo`, `sinabs`, `rockpool`, `brian2`, `pynn`, `akida`). Every notebook targeting these is stuck at 🟡 MODERATE purely because there's no `nir_support.py`-style table to confirm coverage, mirroring the exact ambiguity already flagged for Nengo in the original report. Building this table (even just exact/approximate/unsupported per node type, per target) would let ~9 more notebooks across this analysis move from MODERATE to a confirmed HIGH or a confirmed BLOCKED.

**3. `Affine` unsupported at `lava_sim`.** This blocks even the simplest possible graph (`Affine → LIF`, the entire LIF task) from running on CNLStudio's own built-in Lava simulator, despite `Linear` and `LIF` both being exact. Given `nir_to_lava.py`'s external script already handles `Affine → Dense` mapping, promoting this to `exact` (or `approximate`) in `nir_support.py` looks low-effort relative to the other gaps here.

**4. `rockpool_io` / custom `cnl.*` node coverage is unverified.** Same shape of gap as the Nengo/RSynaptic case already known from the original report — needs the same kind of custom-converter work (or confirmation it already exists) to unblock `rockpool_apply.ipynb`.
