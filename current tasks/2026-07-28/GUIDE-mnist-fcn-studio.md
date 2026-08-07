# Guide: MNIST FCN in CNLStudio — step by step

**This is the canvas guide.** It builds the network and the training pipeline by hand on Studio's
Model, Training and Eval canvases and trains what you built — steps 1 through 6 of the stepper, no
prebuilt demo. It now continues all the way onto the **physical Akida card**; see §10.

Target: snnTorch Tutorial 5 feedforward SNN.
`784 → Linear(1000) → LIF → Linear(10) → LIF → 10`, 25 timesteps, static image repeated each step.

**If you intend to reach the Akida card, build `784 → 256 → 10` instead** — Akida maps 256 neurons
per neural processor. Everything else is identical; §1 flags the two fields to change. Your accuracy
will land somewhat below the §7 figure, which was measured at 1000.

Every label below is the exact text in the Studio UI. Fields not listed are left at their defaults.
Expected result: **~92.5% test accuracy** (measured — see §7).

Last verified against the code on **6 August 2026**.

---

## 0. Before you start — read this, it is the one real gap

You need three files:

| File | Shape | Use |
|---|---|---|
| `mnist_train.pt` | (9000, 784) | training |
| `mnist_val.pt` | (1000, 784) | validation / best-checkpoint selection |
| `mnist_test.pt` | (2000, 784) | final score |

**There is currently no in-app way to produce them, and this is a known gap.** Studio's dataset
catalog is Firebase-backed and today contains one folder of DVS recordings ("Davis 24") — no MNIST
and no `.pt` files. The Data Loader's file picker only *uploads* a file you already have; it does
not create one.

The files in this repo's `workspaces/` were made by
[`prepare_mnist_pt.py`](prepare_mnist_pt.py), a developer script run from a terminal. That is a
developer path, not a user path — an end user should never be asked to run it, so if you are
following this as a user, ask for the files or for the in-app importer to be built.

What the files must contain, if you are supplying your own: a `torch.utils.data.TensorDataset` of
`x` float32 `(N, 784)` and `y` int64 `(N,)`, saved with `torch.save`. It has to load under
`weights_only=True` inside `safe_globals([TensorDataset])`, which is what the generated
`_pt_loading_code` does. The shape is `(N, 784)` and **not** `(N, 1, 28, 28)` on purpose: the
generated `forward()` takes its `x.dim() == 2` branch and expands the same image across all 25
timesteps, which is Tutorial 5's input scheme.

Each Data Loader node has a file picker — select the file there and the `Dataset Path` field fills
itself with the uploaded path. Don't type the `workspaces/...` path by hand.

### Going to the Akida card? Tick it in Setup — yes, always

In **Setup → Target platform**, tick **both** `snnTorch` and **Akida**. Leave both ticked for the
whole journey. This used to be a genuine dilemma; since 6 August 2026 it is not.

Each tile now carries a badge saying what Play does with it:

| Badge | Meaning |
|---|---|
| **Training** | Play trains on this target. Only `snnTorch` has this. |
| **Deploy only** | Play generates a readable notebook and enables hardware pairing, but does **not** run it. |

So ticking **Akida** costs you nothing at Run time. Its tab shows a **grey** dot with a tooltip
explaining that it was not trained, the snnTorch tab trains as normal, and no error banner appears.
Earlier builds executed every selected platform's notebook — which meant ticking Akida ran a
notebook with no training loop and failed, looking like your mistake. The Run step now asks the
backend whether a notebook is trainable (`GenerateV2Response.trainable`, derived from
`_TRAINABLE_NOTEBOOK_TARGETS`) and skips execution when it isn't.

Ticking Akida is what you *want*, because it is now the thing that puts Akida in the Deploy step:

- **Setup owns the platform.** The Deploy step's **Deploy to** dropdown lists only the platforms you
  ticked here. With one platform ticked it collapses to a label. Deploy no longer offers targets you
  never selected.
- **Deploy owns the host.** Picking the machine with the card in it happens in the Akida Runtime
  panel, not in Setup — and you can now **pair a host from that panel directly** ("Pair or select a
  host"). Setup's **Manage Targets** button still works and does the same thing.

**The Akida-platform notebook is still not the path to a trained model on the card.** `akida` has no
training adapter, so it converts whatever weights the CNL spec carries — an untrained network. The
route that puts *your trained model* on the card is the snnTorch notebook's **Akida Exporter** node
(§2 node 11 and §10). Two separate code paths that share the word "Akida".

Its architecture cell **used to crash every time**: `_generate_akida_code`
([notebook.py:1302](../../neurocnl/backend/app/routers/notebook.py:1302)) carried its own copy of the
layer-construction logic and built `akl.InputLayer(...)`, an SDK symbol that does not exist, so the
cell raised `AttributeError: module 'akida.layers' has no attribute 'InputLayer'`. Fixed 6 August
2026 — it now calls `nir_to_akida` from `neurocnl/converter/akida_adapter.py`, the same module the
Akida Exporter uses. Update the backend if you still see the old error.

**If Setup shows no datasets at all** and steps 2-6 stay locked, that is a separate backend fault,
not something you did: the catalog endpoint fails and Setup cannot mark a dataset chosen. Fixed
5 August 2026 (`dataset_cache` was never initialised under Docker, so its registry table was
missing the `source` column); update the backend if you still see it.

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

> **Going to the Akida card?** Change three numbers: node 2 `Rows` = **256**, node 3 `Neurons` =
> **256**, node 4 `Cols` = **256**. Akida maps at most 256 neurons per neural processor, so a
> 1000-unit hidden layer converts and runs in simulation but will not map onto silicon. Nothing
> else in this guide changes.

Wire, `out` → `in` each time:

```
Input → Linear → LIF → Linear → LIF → Output
```

**Notes on the values above**

- `Rows` is the output width, `Cols` the input width — so 784→1000 is `Rows=1000, Cols=784`.
  (Same convention as Braille's 40×12.)
- **`Tau = 0.002` is the one that actually matters.** The generator computes
  `beta = 1 - dt/tau` = `1 - 0.0001/0.002` = **0.95**. Set `Beta` to 0.95 as well; the two agree, so
  it cannot matter which one wins, and §5 verifies the result either way.
  *(Corrected 2026-08-05: an earlier revision warned that `Beta` was read from node metadata rather
  than parameters and might be ignored. `_deserialize_node` now reads every field from `params`, so
  the override does take effect.)*
- **Do not use `cnl.Leaky`** even though it takes beta directly. `CnlLeaky` emits kind
  `leaky_explicit`, which is in `_recurrent_kinds`
  ([notebook.py:970](neurocnl/backend/app/routers/notebook.py:970)), so the generated `forward()`
  switches to the per-timestep `xt` loop variable and crashes on `(batch, 784)` static input.
- `Fill` is irrelevant — weights are dropped in the CNL-text round trip, so every Linear gets
  PyTorch's default init regardless of what you put there.

---

## 2. Canvas: Train

Place nine nodes — or eleven if you are going to the Akida card. (This canvas is labelled
**Training** in the stepper; "Train" and "Training" mean the same canvas throughout this guide.)

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
| 10 | **Test Loader** | file picker → `mnist_test.pt`; `Format` = **pt**; `Batch Size` = **128**. Add this **only if** you are adding node 11 — see the note below. |
| 11 | **Akida Exporter** | all four defaults are correct — `Filename` `model.fbz`, `Weight bits` **4**, `Deploy bundle` **on**, `Eval samples` **2000**. Skip nodes 10 and 11 if you do not care about Akida; nothing else depends on them. |

**Why node 10 exists.** The Akida Exporter scores the converted model against `test_loader`, and a
`.pt` Data Loader binds `test_loader` to *its own* file as a fallback. Without an explicit Test
Loader on this canvas, the exporter would score against `mnist_train.pt` and ship 2000 **training**
images to the card as its evaluation set — an inflated number with nothing to signal it. Node 10 is
what makes the printed accuracies, and the on-card accuracy, real. Leave it unwired: it has `data`
and `labels` outputs, but nothing on this canvas should consume them.

**Do NOT add**: Gradient Clip, Reduce LR on Plateau, L1 Spike Regularization, L2 Spike
Regularization. None are in the tutorial. This is a baseline — it should have nothing to blame.

### Placing the Test Loader and the Akida Exporter

These are the two nodes this guide adds that are not part of the tutorial, and both are easy to
miss in the palette.

**Test Loader** has no edges, so place it with the **Add** button (the `+` in the floating toolbar
at the bottom of the canvas). It opens an **Add Node** dialog: type `test` and pick **Test Loader**.
Then double-tap the placed node to open the Inspector and set its file and fields.

**Akida Exporter** does need an edge, so place it from the port instead — **do it this way and the
node arrives already wired**:

1. On the Train canvas, **tap the `model` output dot on the Adam Optimiser node.** It highlights —
   that is "armed", not connected.
2. **Tap the same dot again.** A dialog titled **Connect to new node** opens. (The port dot doubles
   as the `+`; its tooltip says "Tap to connect, tap again to add a node".)
3. Type `akida` in the search box. One card is left: **Akida Exporter**.
4. Tap that card's **`model`** port row. The node is created next to Adam Optimiser with the edge
   already drawn.

The alternative is the **Add** button (a `+`) in the floating toolbar at the bottom of the canvas,
which opens an **Add Node** dialog. That grid is a flat list with no category headings and around
36 entries, so type `akida` there too rather than hunting — the node sits near the end, between
**NIR Exporter** and **Python Exporter**. Placing it this way leaves it unwired; you then have to
draw the Adam Optimiser edge yourself.

To change its fields, **double-tap the node**; the Inspector opens on the right. (The pipeline
Inspector is desktop-only — there is no toggle button for it on this canvas, so double-tap is the
only way in.)

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
| Adam Optimiser | `model` | Akida Exporter | `model` |
| Data Loader (val) | `data` | Validation Loop | `val_data` |

Nine edges without Akida, ten with it. **Adam Optimiser's `model` output feeds two nodes** —
Validation Loop and Akida Exporter. Every other output in this table is used once, so this is the
one place a second edge from the same dot is correct rather than a mistake.

State Reset's own `model` **input** stays unconnected — only its output matters. Forward Pass's
`membrane` output stays unconnected. Test Loader stays entirely unconnected. Akida Exporter has no
outputs; it is a terminal node.

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
defaults it to on when the field is absent:
`bool(n.parameters.get("load_best_checkpoint", True))`
([notebook.py:2832](neurocnl/backend/app/routers/notebook.py:2832)).

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

With both platforms ticked you get two tabs. Expect **snnTorch green** and **Akida grey**: grey means
its notebook was generated but deliberately not run (hover the tab for the reason). Only red is a
failure, and a red banner now has a **Dismiss** button — dismissing acknowledges the error without
re-running every platform, which is what **Retry** does.

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

Once this matches, you have completed the canvas journey end to end. **Create MNIST Demo** in the
Akida Runtime panel is a *separate* full-MNIST demo — it trains its own model in a prebuilt
notebook and shares nothing with what you built here. See §10 before assuming it continues from
this point.

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

### Converting your trained model to Akida

The **Akida Exporter** node you placed in §2 runs once after the last epoch and prints:

```
snnTorch accuracy : ...
Akida accuracy    : ...
Conversion delta  : ... pp
Deploy bundle     : model.akida-bundle.zip (2000 samples, sha256 ...)
```

It reloads `best_model.pt`, copies the trained weights into the NIR graph, quantizes them, builds a
real `akida.Model`, and evaluates it on your test loader. That evaluation runs on the Akida
**software simulator**, so those first three lines need no card.

The fourth line is the one that matters for hardware. Alongside `model.fbz` the node writes
`model.akida-bundle.zip`, containing the converted model, the quantized evaluation set, and a
checksummed manifest. That is the only artifact any deploy control in Studio looks for.

Parameters: `Filename` (default `model.fbz`), `Weight bits` (1, 2, 4 or 8 — Akida accepts nothing
else), `Deploy bundle` (on), and `Eval samples` (2000 — the cap on what travels in the bundle; the
host refuses anything over 32 MB).

**Constraints for a model that can reach real hardware** — a straight chain, LIF neurons, **≤256
neurons per layer**, no branching or recurrence. The `784 → 1000 → 10` network breaks only the 256
rule, so build **`784 → 256 → 10`** if you care about the card. The exporter still converts a wider
model and prints a warning.

Expect a delta, and treat a large one as information rather than failure: an Akida
`FullyConnected` is a single-pass quantized unit, while what you trained is a temporal LIF network
run over 25 timesteps. If Akida accuracy lands near 10% the exporter says so explicitly — that is
a scaling problem in the conversion, not a problem with your trained model.

*(Record your measured pair here after a run.)*

### Running it on the physical card

Wired up 2026-08-06. After the notebook run finishes:

1. Go to the **Results** step and choose **Deploy to Hardware**.
2. In **Deploy to** pick **Akida**. (It is listed because you ticked it in Setup — see §0. If you
   ticked only Akida, there is no dropdown at all, just the label.) The **Akida Runtime** panel
   appears.
3. Select your paired host. If none is paired the panel now says so in its body and offers **Pair or
   select a host** right there — you no longer have to go back to Setup, though **Manage Targets** on
   the Setup tile still does the same job. The status dot on the Setup tile must not be red.
4. Choose **Use Latest Bundle**. It reports the folder it is searching, then finds the newest
   `*.akida-bundle.zip` there — the one your pipeline just wrote — and submits it. The panel names
   the bundle and its schema version (`v2` for a canvas bundle, `v1` for the MNIST companion), which
   matters because discovery picks by timestamp and a workspace can hold both.
5. Progress runs through validation → loading → mapping → evaluation. The host loads the converted
   model, maps it onto the device, and measures accuracy **on the card**.
6. Enter a **Sample index** and choose **Run Model Sample** to run one image on the silicon.

Which gates apply:

- The 98% source / 96% Akida thresholds are **V1 bundle** rules, written for the MNIST CNN demo.
  They do **not** apply to a canvas bundle. Your model is reported at whatever it scores; only a
  near-chance result (below 20%) fails the job, and that means the conversion scaling is wrong
  rather than your training.
- **Hardware verified** still requires a real device. Studio always asks for physical hardware, so
  with no card present the job fails with `PHYSICAL_HARDWARE_REQUIRED` — that is correct behaviour,
  not a bug. **Run Model Sample** stays disabled until the job is hardware verified.
- Re-running the notebook with identical data and weights produces a byte-identical bundle, and the
  host deduplicates by checksum — you get the *previous* job back rather than a fresh one. Change
  something, or use the previous result.

### If the host refuses the bundle

```
The converted model in this bundle could not be loaded by the Akida runtime.
```

A `.fbz` is a version-gated flatbuffer: only the Akida SDK version that wrote it can reopen it. The
notebook writes it (in the `jupyter-server` image) and the paired host reads it, and those two used
to be pinned differently — `akida>=2.0.0` floating in the image against `akida==2.19.1` fixed on the
host — so the host refused a bundle that had validated cleanly, and the message named no version
because the SDK's own error was thrown away.

Fixed 6 August 2026, three ways:

- Both sides now pin **`akida==2.19.2`** (`workers/jupyter_server/requirements.txt` and
  `akidaRuntime.requiredPackages` in `modules.json`), and
  `scripts/verify_akida_package_manifest.py --pins-only` fails if they ever drift apart again.
- The bundle's manifest has always recorded the producer's SDK version and nothing read it. The host
  now compares it against its own and fails with `MODEL_SDK_VERSION_MISMATCH`, **naming both
  versions** and what to do.
- If the load fails for any other reason, the message now carries the SDK's actual exception instead
  of swallowing it, and the host logs it.

The panel's **Akida SDK version** row shows what the host has installed. After the pin change the
host needs its packages reinstalled — do that from the app's install flow on the Akida tile, not a
terminal.

If the **snnTorch** notebook's Akida Exporter cell itself fails with:

```
ImportError: cannot import name 'AkidaConversionError' from 'neurocnl.converter.akida_adapter'
```

that is a stale `jupyter-server` image, not a code bug — `workers/jupyter_server/Dockerfile` also
`pip install`s `neurocnl` from source (separately from `suite_api`'s copy), so a dev-server update
has to rebuild **both** images. `scripts/dev_update.sh`'s path table only rebuilt `suite_api` for a
`neurocnl/neurocnl/*` change until this was noticed (fixed here); if you are still on an older
`dev_update.sh`, force it: `make dev-update ARGS='--force-rebuild jupyter-server'`.

*(Record the on-card accuracy here after a run.)*

Still true and still not this path: the other Akida route (**Map Runtime** / **Generate Package** /
**Run Inference**) consumes the CNL **spec text** only. `AkidaBackend.construct_model` never calls
`set_weights`, so it maps your topology onto the card with SDK-default weights — an untrained
network. Ignore that group.

Also still true: only `snntorch_sim` has a training adapter
(`_TRAINABLE_NOTEBOOK_TARGETS`, [notebook.py:360](../../neurocnl/backend/app/routers/notebook.py:360)).
Selecting `akida` as the *platform* generates a notebook with no training cell at all — which is why
Play no longer runs it and its Run tab is badged **Deploy only**. Train on `snntorch_sim` and let the
Akida Exporter do the conversion; that is the supported route.

[The Akida companion guide](../2026-08-04/GUIDE-akida-mnist-companion.md) remains a **separate,
self-contained** demo: it trains its own CNN in a prebuilt notebook and ships ONNX for the host to
quantize. Both paths now end at the same panel and the same card, but it teaches you nothing about
the canvases.

Separately: the 794,000-weight FCN above does not fit the fixed PYNQ/SC-NeuroCore overlay
(256 neurons, two populations, 15,360 synapses).
