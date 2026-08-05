# Guide: MNIST FCN in CNLStudio — step by step

Target: snnTorch Tutorial 5 feedforward SNN.
`784 → Linear(1000) → LIF → Linear(10) → LIF → 10`, 25 timesteps, static image repeated each step.

Every label below is the exact text in the Studio UI. Fields not listed are left at their defaults.
Expected result: **~92.5% test accuracy** (measured — see §7).

---

## 0. Before you start

Three files are already generated and sit in `workspaces/`:

| File | Shape | Use |
|---|---|---|
| `mnist_train.pt` | (9000, 784) | training |
| `mnist_val.pt` | (1000, 784) | validation / best-checkpoint selection |
| `mnist_test.pt` | (2000, 784) | final score |

For the full-MNIST companion, use **Akida Runtime → Create MNIST Demo** in Studio. The generated
embedded notebook downloads MNIST, trains, verifies ONNX parity, and creates the deployment bundle.

Each Data Loader node has a file picker — select the file there and the `Dataset Path` field fills
itself with the uploaded path. Don't type the `workspaces/...` path by hand.

---

## 1. Canvas: Model

Place six nodes and set these fields.

| # | Node (palette name) | Fields to set |
|---|---|---|
| 1 | **Input** | `Size` = **784** |
| 2 | **Linear** | `Rows` = **1000**, `Cols` = **784**, `Fill` = leave as is |
| 3 | **LIF** | `Neurons` = **1000**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta (mem decay)` = **0.95** |
| 4 | **Linear** | `Rows` = **10**, `Cols` = **1000**, `Fill` = leave as is |
| 5 | **LIF** | `Neurons` = **10**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta (mem decay)` = **0.95** |
| 6 | **Output** | `Size` = **10** |

Wire, `out` → `in` each time:

```
Input → Linear → LIF → Linear → LIF → Output
```

**Notes on the values above**

- `Rows` is the output width, `Cols` the input width — so 784→1000 is `Rows=1000, Cols=784`.
  (Same convention as Braille's 40×12.)
- **`Tau = 0.002` is the one that actually matters.** The generator computes
  `beta = 1 - dt/tau` = `1 - 0.0001/0.002` = **0.95**. The `Beta` field is a documented override
  ("leave blank to derive from tau/dt") but it is stored in the node's *parameters*, while the
  generator reads it from the node's *metadata*
  ([nir_graph_serializer.py:588](neurocnl/backend/app/services/nir_graph_serializer.py:588)) — so it
  may not take effect. Set both; they agree, so it can't matter which one wins. Step 5 verifies the
  result either way.
- **Do not use `cnl.Leaky`** even though it takes beta directly. It is classified as a recurrent
  node ([notebook.py:954](neurocnl/backend/app/routers/notebook.py:954)) and would generate a
  time-series forward that crashes on `(batch, 784)` input.
- `Fill` is irrelevant — weights are dropped in the CNL-text round trip, so every Linear gets
  PyTorch's default init regardless of what you put there.

---

## 2. Canvas: Train

Place nine nodes.

| # | Node | Fields to set |
|---|---|---|
| 1 | **Data Loader** (train) | file picker → `mnist_train.pt`; `Format` = **pt**; `Batch Size` = **128**; `Shuffle` = **on** |
| 2 | **State Reset** | none |
| 3 | **Forward Pass** | none (panel is read-only) |
| 4 | **Time Loop** | `Num Steps` = **25** (already the default) |
| 5 | **CE Count Loss** | none |
| 6 | **Surrogate Backward** | `Function` = **fast_sigmoid**, `Slope` = **25** (both already default) |
| 7 | **Adam Optimiser** | `Lr` = **0.0005** ← *the only change*; leave `Weight Decay` 0.0, `Beta1` 0.9, `Beta2` 0.999 |
| 8 | **Data Loader** (val) | file picker → `mnist_val.pt`; `Format` = **pt**; `Batch Size` = **128**; `Shuffle` = **off** |
| 9 | **Validation Loop** | all four defaults are already correct — `Every N Epochs` 1, `Save Best Checkpoint` **on**, `Checkpoint Metric` `val_accuracy`, `Checkpoint Mode` `max` |

**Do NOT add**: Gradient Clip, Reduce LR on Plateau, L1 Spike Regularization, L2 Spike
Regularization. None are in the tutorial. This is a baseline — it should have nothing to blame.

### Wiring (source port → target port)

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
| Data Loader (val) | `data` | Validation Loop | `val_data` |

Nine edges. State Reset's own `model` **input** stays unconnected — only its output matters.
Forward Pass's `membrane` output stays unconnected.

---

## 3. Pipeline Settings

Toolbar button on the **Training** canvas (not a node panel).

- `Epochs` = **5**
- `Batch Size` = **128**
- `Loss Function` = **ce_count**

Only `Epochs` actually drives codegen — the canvas nodes win for batch size and loss. Set the other
two anyway so the dialog doesn't silently disagree with the canvas, which is what made the Braille
workspace hard to read.

---

## 4. Canvas: Eval

| # | Node | Fields to set |
|---|---|---|
| 1 | **Data Loader** (test) | file picker → `mnist_test.pt`; `Format` = **pt**; `Batch Size` = **128**; `Shuffle` = **off**; `Load Best Checkpoint` = **on** if the toggle is shown |
| 2 | **Time Loop** | `Num Steps` = **25** — see the warning in §5 |
| 3 | **State Reset** | none |
| 4 | **Forward Pass** | none (Eval Mode is automatic from the canvas it sits on) |
| 5 | **Accuracy** | `Top K` = **1** (already default) |

### Wiring

| From | port | To | port |
|---|---|---|---|
| Data Loader (test) | `data` | Forward Pass | `input` |
| Data Loader (test) | `labels` | Accuracy | `labels` |
| State Reset | `model` | Forward Pass | `model` |
| Forward Pass | `spikes` | Accuracy | `spikes` |

If the `Load Best Checkpoint` toggle isn't visible on this node, don't worry — the generator
defaults it to on when the field is absent
([notebook.py:2602](neurocnl/backend/app/routers/notebook.py:2602)).

---

## 5. Generate, then read four lines before running

Go to Step 5 (Jupyter Lab) and generate. Check these in the notebook **before** you run anything:

1. **Architecture cell** contains, twice:
   `snn.Leaky(beta=0.950000, threshold=20.0000, reset_mechanism='zero', init_hidden=True, ...)`
   If beta is not `0.950000`, the tau→beta conversion didn't land as expected. Read the `dt` the
   generator used and set `Tau = dt / 0.05` instead. The effective threshold is 20 because the NIR
   resistance/input scale is `r × dt / tau = 0.05`; the snnTorch and Sinabs adapters both apply this
   same correction.
2. **Architecture cell** says `Net: 794000 parameters`.
3. **Train cell** contains `torch.optim.Adam(net.parameters(), lr=0.0005, ...)` and
   `for epoch in range(5)`.
4. **`num_steps = 25` is bound before any `net(data)` call.**

⚠️ **On #4** — the generated `forward()` reads the timestep count as
`globals().get('num_steps', 1)`. `num_steps = 25` is emitted by the Time Loop node. Train and Eval
share one kernel, so Eval normally inherits it, but if Eval ever runs *without* Train having run
first, the network silently uses **one** timestep and accuracy drops to roughly 10% with no error
message. Always run Train before Eval.

---

## 6. Run

Step 6 (Results), or run the cells in Jupyter. The eval cell must print
`Loaded best checkpoint from best_model.pt` before the accuracy line. If it prints
`best_model.pt not found — evaluating with current in-memory weights`, the number you get is the
last-epoch model rather than the best one — that is a real problem, not a cosmetic warning.

---

## 7. What you should see

Measured by running the exact generated code against these exact `.pt` files, seed 42:

| epoch | train loss | val accuracy |
|---|---|---|
| 1 | 0.9241 | 89.40% |
| 2 | 0.2475 | 93.00% |
| 3 | 0.1692 | 93.00% |
| 4 | 0.1408 | 93.10% |
| 5 | 0.1012 | **95.00%** |

**Test accuracy: 92.45% (1849/2000).** Output spike rate settles around 0.04.

Validation peaks at epoch 5 and dips at 6 — mild overfitting. Don't raise the epoch count.

Once this matches, use **Create MNIST Demo** in the Akida Runtime panel for the separate full-MNIST
companion. That notebook uses all 60,000 training and 10,000 test examples without requiring a
local preparation command.

---

## 8. If the number is wrong

| You see | Likely cause |
|---|---|
| ~10% (chance) | `num_steps` fell back to 1 — Eval ran without Train in the same kernel (§5 #4) |
| ~10%, and beta reads `0.995000` | `Tau` left at its 0.02 default; set 0.002 |
| 40–70% | Something in the Studio's generated code differs from the verified version — diff the train cell against §5 |
| **val ≫ test (e.g. 96% val, 82% test)** | **The val Data Loader clobbered `train_loader`** — see below. Fixed 2026-07-28; only affects notebooks generated before that. |
| ~85–89% | Only one epoch's worth of training landed, or `Lr` left at the 0.001 default |
| Shape error in `nn.Linear` | A `cnl.Leaky` was used instead of `nir.LIF` (§1) |

### The val-loader clobber (fixed 2026-07-28)

Both Data Loader nodes emitted `_pt_loading_code`, which always binds `train_loader` **and**
`test_loader`. The val loader sorted second, so its block overwrote `train_loader` with
`mnist_val.pt` — the run trained on the 1000 validation samples and then "validated" on those
same samples. Val read 95.8% (really train accuracy) and test read 82.25%.

Two ways to confirm you are looking at an affected notebook:

- The train cell contains **two** `train_loader = DataLoader(...)` assignments, the second
  loading the val file. A fixed notebook has one, plus a separate `val_loader = DataLoader`.
- The train cell prints only one `.pt dataset:` line before the validation line. Fixed output
  prints both `.pt dataset: 9000 samples, batch_size=128` and
  `.pt validation dataset: 1000 samples, batch_size=128`.

Regenerate the notebook to fix it; nothing on the canvas needs changing. The same wiring is
in `workspaces/to-test.nmtk`, so pre-fix Braille runs trained on their validation split too.

---

## 9. After this works

Back to Braille, in this order:

1. Check which checkpoint line the old 42% run printed (§6). That alone may explain it.
2. Rebuild Braille as bare reference: Adam `lr=0.001`, 500 epochs, batch 64, CE Count Loss,
   L1 0.001 / L2 1e-6, fast_sigmoid slope 5, **no Gradient Clip, no Reduce LR on Plateau** — neither
   exists in the reference notebook.
3. Only then re-add the two stability nodes, one run at a time.

---

## 10. Multi-framework proof: trained NIR → Sinabs

The Studio training loop is verified only for **snnTorch**. Sinabs, Nengo, Brian2, PyNN,
Rockpool, Lava, SC-NeuroCore, and the CNL-mapped Akida target are shown as inference/code-generation
targets; Studio will no longer place their generated models inside the generic snnTorch optimizer
loop.

To demonstrate a second framework without retraining a different model:

1. Add **NIR Exporter** to the Train canvas and leave `Filename` as `model.nir`.
2. Generate the snnTorch notebook and run it through evaluation. The exporter runs once after the
   last epoch, reloads `best_model.pt`, and copies every trained Linear/Affine tensor into `model.nir`.
3. Import `model.nir` in the Architecture step, select **Sinabs**, and generate a new notebook.
4. Run evaluation. The Sinabs wrapper resets state per batch, presents each image for 25 timesteps,
   and returns time-first spike counts compatible with Studio's Accuracy node.

Sinabs remains labeled **approximate** because its discrete LIF/reset implementation is mapped from
the effective snnTorch decay and threshold rather than being the original training runtime. The
2,000-sample acceptance gate is snnTorch accuracy ≥92%, Sinabs accuracy ≥90%, and prediction
agreement ≥90%; record the measured values in this guide after a verified run.

For physical Akida inference, go to **Results → Deploy to Hardware → Akida → Akida Runtime** and
continue with [the companion guide](../2026-08-04/GUIDE-akida-mnist-companion.md). The existing
794,000-weight FCN does not fit the fixed PYNQ/SC-NeuroCore overlay (256 neurons, two populations,
15,360 synapses).
