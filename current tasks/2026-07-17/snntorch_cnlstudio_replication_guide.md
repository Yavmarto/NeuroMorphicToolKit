## ⚠️ Correction (2026-07-17) — pulled back out of archive, status downgraded

This file was mistakenly filed as historical/done in the 2026-07-17 cleanup. It is not done. Everything below is **untested design-time work**: the doc's own line 6 says it was "checked against live code" — i.e. someone read the source and confirmed the parameter names/wiring *should* work — nobody has actually opened CNLStudio, built these graphs, run them, and confirmed the notebook's original numeric results come out the other end. "Replicable" and "shipped ✅" in this doc and in `cnlstudio_notebook_analysis.md`'s P0–P5 backlog describe **feature/capability presence** (the node exists, the parameter is named correctly), not a verified replication. Real remaining work: actually run all 3 written guides (Tutorial 3 feedforward, Braille RNN, the 4-notebook LIF group) end-to-end in a live CNLStudio instance and confirm they reproduce the original notebooks' results, then do the same for the 9 still-unwritten guides once written.

## ⚠️ Second correction (2026-07-17) — this whole doc only ever covered a subset of the notebooks in the repo

Everything above only concerns notebooks living under `paper/` (the vendored NIR-paper repo), which turns out to actually hold **4 separate notebook collections**, not 1:
- `paper/01_lif/`, `02_cnn/`, `03_rnn/` — NMTK's own ~38-40 NIR-paper notebooks (this doc's actual subject).
- `paper/Spiking-Neural-Networks-Tutorials-main/` — 6 third-party intro tutorials.
- `paper/notebooks-main/` — 12 official Norse tutorials.
- `paper/spikingjelly-master/community_tutorials/jupyter/chinese/` — 5 Chinese-language SpikingJelly tutorials.

That's ~59-63 notebooks total under `paper/` alone, of which only 10 are even on the curated "reproducible" list (`agent-tests/reproducible_notebooks.md`), only 3 groups have written guides (this doc), and **zero have been actually run end-to-end in CNLStudio.**

**On top of that, a real notebook collection outside `paper/` has never been assessed at all: `Neuro-Dream-Hand/`** (NMTK's own submodule) — `demo.ipynb` plus 6 example notebooks under `Neuro-Dream-Hand/examples/` (`example_conveyor.ipynb`, `example_dynamic_mass.ipynb`, `example_fragile_grasp.ipynb`, `example_noisy_sensors.ipynb`, `example_phantom_limb.ipynb`, `example_prosthetic_fatigue.ipynb`) — Nengo/MuJoCo prosthetic-hand demos. Nobody has done any CNLStudio-replicability analysis on these 7 at all — no P0-P5-style backlog, no ranking, no guide, nothing. This needs its own pass from scratch.

Two more notebook locations exist but are **not** replication targets — noted so they don't get mistaken for new sources:
- `workers/jupyter_server/notebooks/00_nmtk_quickstart.ipynb` — NMTK's own in-app product quickstart notebook, not an external tutorial.
- `gen test/` (9 notebooks + `MANIFEST.md`) — this is CNLStudio's own *generated output* from a prior codegen test pass, not a source to replicate. Its manifest was never actually read until now; it contains two real findings worth folding in:
  - Confirms (again) `snntorch_apply`/`cnn_sinabs.nir` is `unsupported` (real `SumPool2d`, not `AvgPool2d`) — consistent with the correction already in this doc.
  - **New finding, not previously captured anywhere:** the 3 Braille notebooks classify as `approximate`, not `exact` — `cnl.RSynaptic`/`cnl.Synaptic` get flattened to raw `nir.CubaLIF`+`nir.Linear` at NIR export time, and `CubaLIF` is only `approximate` for `snntorch_sim`. This is expected/correct behavior, not a bug, but it means Guide 2 below (Braille RNN) should not be read as reproducing the original `snn.RSynaptic`/`snn.Synaptic` dynamics exactly — the generated code uses `snn.Leaky` with synaptic current filtering explicitly not modeled. All 9 `gen test/` notebooks did generate without exceptions and validated as well-formed — that's confirmation the *codegen* works, still not confirmation the *replication* is correct (no cell was actually executed).

---

# CNLStudio Replication Guide: snnTorch Tutorials (consolidated, corrected)

**Date:** 16 July 2026
**Supersedes:** `current tasks/2026-07-13/snntorch_cnlstudio_guide.md`, `current tasks/2026-07-13/tutorial_replication_report.md`, `current tasks/2026-07-14/snntorch_training_cnlstudio_guide.md`, `current tasks/16 june/cnlstudio_notebook_new_guides.md` (all four deleted — content merged and corrected here).

This doc verifies the prior guides against the current `neurocnl` codebase and folds them into one file. Everything below was checked against live code, not assumed from the older docs.

---

## What changed since the old guides were written

Four things drifted; everything else in the old guides still holds.

1. **Validation Loop no longer has an `Epochs` field.** It was removed from that node's own property panel (`neurocnl` commit `4b915435`). Epoch count now lives in a global **Pipeline Settings** dialog, opened from a toolbar button on the **Training canvas** (added in commit `393d403d`), range 1–2000. Any step that says "set Epochs in the Validation Loop node's panel" is wrong — open Pipeline Settings from the Training canvas toolbar instead.
2. **RSynaptic/Synaptic reset param is named `reset_mechanism`, not `reset`.** Full current param set: `n_neurons`, `alpha`, `beta`, `threshold`, `reset_mechanism` (enum: subtract/zero); RSynaptic additionally has `use_bias` (bool).
3. **Forward Pass has no editable parameters.** Its property panel shows a read-only "Eval Mode" indicator, derived automatically from which canvas (Train vs. Eval) the node sits on. There is no `eval_mode` field to set — just place the node on the Eval canvas.
4. **"Load Best Checkpoint" now actually works.** Before commit `23e7bcb8` this toggle was cosmetic — the backend never read it. Now the generated eval code actually loads `best_model.pt` before scoring when the toggle is on, and the toggle now also appears on plain eval-phase Data Loader nodes (previously Test Loader only). If you followed an older guide and enabled this, it will now behave as originally intended.

Everything else — `LIF` (`n_neurons`/`tau`/`threshold`/`r`/`v_leak`, plus new optional `dt`/`beta`), `Linear`/`Affine` (`rows`/`cols`/`weight_fill`, no bias field), `Data Loader` (`format`/`dataset_path`/`batch_size`/`shuffle`), `Spike Generator` (`pattern`: `isi_regular`/`poisson`/`constant_rate`), `NIR Exporter` (`filename`), and the per-backend NIR support table (see Deploy-target notes below) — is unchanged and confirmed current.

---

## Replication ranking

| Rank | Notebook | Why |
|---|---|---|
| 🥇 1 | `Spiking-Neural-Networks-Tutorials-main/tutorial_3_feedforward_snn.ipynb` | Simplest graph, no training loop, uses the built-in Spike Generator (no manual stimulus file needed). Only correction needed: Forward Pass note (#3). |
| 🥈 2 (tie) | `paper/01_lif/lif_norse.ipynb`, `lif_rockpool.ipynb`, `lif_nengo.ipynb`, `lif_sinabs.ipynb` | Even simpler (1 neuron), but each needs a one-time manual `.pt` stimulus export since the hand-built spike pattern isn't reproducible by the parametric Spike Generator. |
| 🥉 3 | `paper/03_rnn/Braille_training_snntorch.ipynb` | Most valuable (full training: recurrent nodes, optimizer, regularizers, validation loop) but most moving parts, and the one with corrections #1 and #2 above. |
| — | `notebooks-main` (Norse, general) | Runs seamlessly in NMTK's PyTorch notebook kernel; good NeuroStudio candidates for simple examples, same as before. |
| — | `spikingjelly-master` | Needs `pip install spikingjelly` in the Notebooks env; ANN→SNN conversion and deep conv-SNN examples aren't NeuroStudio-buildable from scratch — best used inside Notebooks + Neurobench, not as a UI-replication target. |

---

## Guide 1: Tutorial 3 — Feedforward SNN

**Target:** `Spiking-Neural-Networks-Tutorials-main/tutorial_3_feedforward_snn.ipynb`
Architecture: `784 → Linear → LIF → Linear → LIF → 10`, `beta=0.99` each layer.

Parameter conversion: `tau = dt/(1-beta)`. With `dt=0.01`, `beta=0.99` → `tau=1.0`, `threshold=1.0`, `r=1`, `v_leak=0`.

**Canvas: Model**
1. **Input:** `n_neurons=784`.
2. **Linear:** `rows=784`, `cols=1000`, `weight_fill=0.05`.
3. **LIF:** `n_neurons=1000`, `tau=1.0`, `threshold=1.0`, `r=1`, `v_leak=0`.
4. **Linear:** `rows=1000`, `cols=10`, `weight_fill=0.05`.
5. **LIF:** `n_neurons=10`, `tau=1.0`, `threshold=1.0`, `r=1`, `v_leak=0`.
6. **Output:** `n_neurons=10`.
7. Wire: `Input → Linear → LIF → Linear → LIF → Output`.

**Canvas: Train** (export only — this notebook has no training loop)
8. **NIR Exporter:** `filename=snntorch_fcn.nir`.
9. Connect Forward Pass (`model` out) → NIR Exporter (`model` in).

**Canvas: Eval**
10. **Spike Generator:** `pattern=poisson`, `n_neurons=784`, `rate_hz=0.5` (approximates the notebook's `spikegen.rate_conv(torch.rand((200,784)))`).
11. **State Reset:** add to canvas (its own `model` input stays unconnected — it and Forward Pass both operate on the single compiled model regardless of that port's wiring; only its `model` *output* into Forward Pass matters).
12. **Forward Pass:** place on the Eval canvas (Eval Mode is automatic — see correction #3, nothing to set).
13. Connect: Spike Generator (`spikes`) → Forward Pass (`input`); State Reset (`model` out) → Forward Pass (`model` in).

*(Optional: to use the notebook's exact `torch.rand` stimulus instead of Poisson noise, export it to `.pt` and swap in a Data Loader node, `format=pt`.)*

**Results**
14. Results step → Dynamics tab → select the final (10-neuron) LIF node. Spike Raster mirrors the notebook's `spikeplot.spike_count`/`splt.traces` output.

---

## Guide 2: Braille RNN training

**Target:** `paper/03_rnn/Braille_training_snntorch.ipynb` — trains a spiking RNN classifying 7 letter categories from 12-channel tactile input over 256 timesteps.

```
Input (12) → Linear(12→40, no bias) → RSynaptic(alpha=0.75, beta=0.85, recurrent, reset=subtract) [40]
           → Linear(40→7, no bias) → Synaptic(alpha=0.45, beta=0.7, reset=subtract) [7] → Output (7)
```
Config values (from `paper/03_rnn/data/parameters_noDelay_noBias_ref_subtract.json`): `N_hidden=40`, `alpha_r=0.75`, `beta_r=0.85`, `alpha_out=0.45`, `beta_out=0.7`, `lr=0.001`, `slope=5`, `reg_l1=0.001`, `reg_l2=0.000001`.

**Canvas: Model**
1. **Input:** `Size=12`.
2. **Linear:** `Cols=12`, `Rows=40` (no bias field exists in the UI regardless).
3. **cnl.RSynaptic:** `n_neurons=40`, `alpha=0.75`, `beta=0.85`, `reset_mechanism=subtract` (corrected — not "Reset"), `use_bias=false`.
4. **Linear:** `Cols=40`, `Rows=7`.
5. **cnl.Synaptic:** `n_neurons=7`, `alpha=0.45`, `beta=0.7`, `reset_mechanism=subtract`.
6. **Output:** `Size=7`.
7. Wire: `Input → Linear → cnl.RSynaptic → Linear → cnl.Synaptic → Output`.

**Canvas: Training**
8. **Data Loader (Train):** `format=pt`, `dataset_path=paper/03_rnn/data/ds_train.pt`, `batch_size=64`, `shuffle=true`.
9. **State Reset** and **Forward Pass**: add to canvas (Forward Pass has no params to set).
10. **Time Loop:** `Time Steps=256`.
11. **CE Count Loss:** add to canvas — this node has no configurable parameters in the UI (equivalent to `SF.ce_count_loss()` with defaults).
12. **l1SpikeReg:** `weight=0.001`, `target_layer=cnl.RSynaptic`.
13. **l2SpikeReg:** `weight=0.000001`, `target_layer=cnl.RSynaptic`.
14. **Surrogate Backward:** `function=fast_sigmoid`, `slope=5`.
15. **Adam Optimizer:** `lr=0.001`.
16. **Data Loader (Val):** `format=pt`, `dataset_path=paper/03_rnn/data/ds_val.pt`, `batch_size=64`, `shuffle=false` → connect to a **Validation Loop** node.
17. Wire:
    - Data Loader (Train) `data` → Forward Pass `input`
    - Data Loader (Train) `labels` → CE Loss `labels`
    - State Reset `model` → Forward Pass `model`
    - Forward Pass `spikes` → Time Loop `spikes`
    - Time Loop `spikes` → CE Loss `spikes`, → l1SpikeReg `spikes`, → l2SpikeReg `spikes`
    - CE Loss `loss` → l1SpikeReg `loss_in`
    - l1SpikeReg `loss` → l2SpikeReg `loss_in`
    - l2SpikeReg `loss` → Surrogate Backward `loss`
    - Surrogate Backward `gradients` → Optimizer `gradients`
    - Optimizer `model` → Validation Loop `model`
    - Data Loader (Val) `data` → Validation Loop `val_data`
18. **Validation Loop:** enable `save_best_checkpoint` (bool, default on); optionally set `checkpoint_metric`/`checkpoint_mode`. **Epochs is not set here** (correction #1) — instead, click **Pipeline Settings** on the Training canvas toolbar and set `Epochs=500` there.
19. Proceed to Step 5 (Jupyter Lab) to generate/review/run the training code, or Step 6 (Results) to run training and watch live loss/accuracy curves.

**Canvas: Eval**
20. **Data Loader (Test):** `format=pt`, `dataset_path=paper/03_rnn/data/ds_test.pt`, `batch_size=64`, `shuffle=false`, enable `load_best_checkpoint` — this toggle now genuinely loads the best checkpoint before scoring (correction #4; it was a no-op in earlier builds).
21. **State Reset**, **Forward Pass** (Eval canvas, no params — correction #3), **Accuracy** node.
22. Wire: Data Loader (Test) `data` → Forward Pass `input`; Data Loader (Test) `labels` → Accuracy `labels`; State Reset `model` → Forward Pass `model`; Forward Pass `spikes` → Accuracy `spikes`.
23. Run evaluation via Step 5 or Step 6 (expected test accuracy ≈92%).

**Results**
24. Results step → Dynamics tab → select the **cnl.RSynaptic** hidden layer to inspect its Spike Raster / recurrent activity.

---

## Guide 3: single-neuron LIF tutorials (`01_lif/*`)

All four share one base architecture: `Linear(1×1, weight_fill=W) → LIF(tau=0.0025, threshold=0.1, r=1, v_leak=0)`, driven by a 1000-step hand-built binary spike train (`d0`, expanded 10×) that the parametric Spike Generator can't reproduce — export it once to a `.pt` file instead.

**One-time stimulus export** (run outside CNLStudio):
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

**Common Model + Eval steps** (all four notebooks):
1. **Input:** `n_neurons=1`.
2. **Linear:** `rows=1`, `cols=1`, `weight_fill=W` (see per-notebook value below).
3. **LIF:** `n_neurons=1`, `tau=0.0025`, `threshold=0.1`, `r=1`, `v_leak=0`.
4. **Output:** `n_neurons=1`.
5. Wire: `Input → Linear → LIF → Output`.
6. **Data Loader:** `format=pt`, `dataset_path=paper/01_lif/data/lif_stimulus_d.pt`, `batch_size=1`, `shuffle=false`.
7. **State Reset**: add to canvas (own `model` input left unconnected, same reasoning as Guide 1 step 11).
8. **Forward Pass:** place on Eval canvas — Eval Mode is automatic (correction #3), no field to set.
9. Wire: Data Loader `data` → Forward Pass `input`; State Reset `model` out → Forward Pass `model` in. Leave Forward Pass's other outputs (e.g. `membrane`) unconnected — no Accuracy node needed, this is a raw trace, not a labeled classification task.

Per-notebook differences:

| Notebook | `weight_fill` | Deploy target | Support tier | Notes |
|---|---|---|---|---|
| `lif_norse.ipynb` | `1` | — (pure forward pass) | — | `Linear`/`LIF` here are model-authoring, not deploy; add **NIR Exporter** (`filename=lif_norse.nir`) on the Train canvas instead of a Deploy step. |
| `lif_rockpool.ipynb` | `0.04` (from `c[0].weight.data.fill_(.04)`) | — (pure forward pass) | — | Same as above; export `filename=lif_rockpool.nir`. Also model-authoring in Rockpool, not a deploy-to-Rockpool scenario. |
| `lif_nengo.ipynb` | `1` | Nengo | Approximate | `Linear` exact, `LIF` approximate (only valid since `r=1`,`v_leak=0` here — nengo raises otherwise). No NIR Exporter needed: Deploy compiles NIR live from the model spec regardless of whether an Exporter node ran. Deploy step shows an amber "Approximate" badge — expected. |
| `lif_sinabs.ipynb` | `1` | Sinabs | Approximate | Only `tau` survives conversion; `threshold`/`v_leak`/`r` reset to sinabs' own `LIF` defaults — don't expect exact numeric parity with the notebook's `v_th=0.1`. Same "no Exporter needed" note as Nengo. |

**Results:** Results step → Dynamics tab → select the LIF node; Membrane Voltage Trace + Spike Raster reproduce each notebook's plot.

---

## Deploy-target block notes (still current, unchanged from the 16 june doc)

- **`02_cnn/nengo.ipynb` — 🔴 BLOCKED.** Architecture needs `Conv2d`, `Flatten`, and `SumPool2d`; the nengo backend's support table (`neurocnl/neurocnl/runtime/nir_support.py`) marks all three `"unsupported"`. No UI workaround short of removing the convolutions, which isn't this notebook.
- **`03_rnn/rockpool_apply.ipynb` — 🔴 BLOCKED.** The Braille RNN graph needs `Synaptic`/`RSynaptic` throughout; rockpool's converter (`rockpool_io.py`, `from_nir()`) only branches on `Linear`/`LIF`/`CubaLIF` and raises on anything else — matches the support table's `"unsupported"` verdict for both node types on this backend.
- **`02_cnn/snntorch_sim_fixed.ipynb` — doesn't exist.** Confirmed via repo-wide search and full git history — never added on any branch. Closest match is `paper/02_cnn/snntorch_apply.ipynb`, already covered elsewhere. The `PadTensors(batch_first=...)` bug this phantom notebook was said to fix can't occur in CNLStudio anyway: the backend hardcodes `batch_first=False` for all `tonic_*` Data Loaders — it isn't a user-configurable UI field.
