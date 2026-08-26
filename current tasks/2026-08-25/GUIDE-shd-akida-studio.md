# Guide: SHD spoken-digit classifier in CNLStudio, Akida variant — step by step

**This is the canvas guide.** It builds the network and training pipeline by hand on Studio's
Model, Training and Eval canvases, same as [GUIDE-mnist-fcn-studio.md](../2026-07-28/GUIDE-mnist-fcn-studio.md)
does for MNIST. It targets a genuinely multivariate spike-timeseries dataset (SHD — Spiking
Heidelberg Digits, 700 input channels, 20 spoken-digit classes) instead of a static image, and
goes all the way to the physical Akida card.

Target: `700 → Linear(128) → LIF → Linear(20) → LIF → 20`, 25 timesteps (padded via tonic's
`ToFrame`, `time_window_ms=4`).

**This is a smaller network than the dataset's full-fidelity template.** The existing
`shd_digit_classifier` template encodes the input through a 700-neuron `cochlea` LIF stage
(one neuron per channel) before the hidden layer — that stage cannot reach Akida, because Akida
maps at most **256 neurons per neural processor** and 700 > 256. This guide's network drops that
stage and feeds the input straight into a 128-neuron hidden layer instead, the same tradeoff the
MNIST guide makes going from `784 → 1000 → 10` (simulator-only) to `784 → 256 → 10` (Akida-ready).
Expect somewhat lower accuracy than a cochlea-preserving, simulator-only run.

Every label below is the exact text in the Studio UI. Fields not listed are left at their
defaults. There is no measured accuracy figure yet — see §7.

Last verified against the code on **26 August 2026**.

---

## 0. Before you start

Unlike MNIST, **the dataset has a real in-app path already** — no `.pt` file wrangling needed.
In **Setup → Dataset**, select **SHD**. The generated notebook downloads the real SHD archive
itself via `tonic.datasets.SHD` the first time it runs; Setup's own download status is just
evidence the catalog path works, it is not the notebook's actual data source.

### Going to the Akida card? Tick it in Setup — yes, always

Same as MNIST: in **Setup → Target platform**, tick **both** `snnTorch` and **Akida**, and leave
both ticked. `snnTorch` trains; `Akida` is **Deploy only** — its tab shows a grey dot and is not
executed at Run time. Ticking it is what puts Akida in the Deploy step's **Deploy to** dropdown.

There is no training adapter for the `akida` platform itself — the route to a *trained* model on
the card is the snnTorch notebook's **Akida Exporter** node (§2, node 8, and §7).

---

## 1. Canvas: Model

Place six nodes and set these fields.

| # | Node (palette name) | Fields to set |
|---|---|---|
| 1 | **Input** | `Size` = **700** |
| 2 | **Linear** | `Rows` = **128**, `Cols` = **700**, `Fill` = leave as is |
| 3 | **LIF** | `Neurons` = **128**, `Tau` = **0.02**, `Threshold` = **0.6**, `Resistance` = **1.0**, `Leak` = **0.0** |
| 4 | **Linear** | `Rows` = **20**, `Cols` = **128**, `Fill` = leave as is |
| 5 | **LIF** | `Neurons` = **20**, `Tau` = **0.03**, `Threshold` = **0.7**, `Resistance` = **1.0**, `Leak` = **0.0** |
| 6 | **Output** | `Size` = **20** |

Wire, `out` → `in` each time:

```
Input → Linear → LIF → Linear → LIF → Output
```

On empty canvas (deselect every node), the property panel shows **Network Settings** — set
**Network Timestep (s)** = **0.001**.

**Shortcut**: this exact network is also a one-click gallery template — **SHD Spoken-Digit
Classifier (Akida)** (`shd_digit_classifier_akida`, category "Signal Processing"). Loading it does
the same as steps 1-6 above.

**Notes on the values above**

- `Rows` is the output width, `Cols` the input width — 700→128 is `Rows=128, Cols=700`.
- The LIF node has **no `Time Step` or `Beta` field** — those used to exist but were dead controls
  (never read by the backend) and have been removed. Timestep is set once, network-wide, in
  **Network Settings**, not per neuron.
- `Tau`/`Threshold` values above are carried over unchanged from the proven-working full-fidelity
  `shd_digit_classifier` template's own `hidden`/`classes` populations — not invented.
- `Fill` is irrelevant — weights are dropped in the CNL-text round trip; every Linear gets its
  default init regardless.

---

## 2. Canvas: Training

Place eight nodes — the Training DAG auto-builds a default chain the first time you open the tab;
edit it in place rather than rebuilding from scratch.

| # | Node | Fields to set |
|---|---|---|
| 1 | **Data Loader** (train) | `Format` = **tonic_shd**; `Batch Size` = **32**; `Shuffle` = **on**; `Time Window (ms)` = **4** |
| 2 | **State Reset** | none |
| 3 | **Forward Pass** | none (panel is read-only) |
| 4 | **Time Loop** | `Num Steps` = **25** (already the default — tonic's framing controls the actual padded sequence length once `Time Window (ms)` is set) |
| 5 | **CE Count Loss** | replace the default `mseCountLoss` node with this one — there is no `ceRateLoss` node, do not add that name by hand |
| 6 | **Surrogate Backward** | `Function` = **fast_sigmoid**, `Slope` = **25** (both already default) |
| 7 | **Adam Optimiser** | `Learning Rate` = **0.001**; `Weight Decay` 0.0, `Beta 1` 0.9, `Beta 2` 0.999 (all already default) |
| 8 | **Akida Exporter** | all four defaults are correct — `Filename` `model.fbz`, `Weight bits` **4**, `Deploy bundle` **on**, `Eval samples` **2000**. Skip this node if you don't care about Akida. |

Add a validation branch:

| # | Node | Fields to set |
|---|---|---|
| 9 | **Test Loader** | `Format` = **tonic_shd**; `Batch Size` = **32**; `Shuffle` = **off**; `Time Window (ms)` = **4** — wire its `data` output to **Validation Loop**'s `val_data` input |
| 10 | **Validation Loop** | `Validate Every N Epochs` **1**, `Save Best Checkpoint` **on**, `Checkpoint Metric` `val_accuracy`, `Checkpoint Mode` `max` (all already default) |

**Unlike the MNIST guide, no separate "Test Loader" node is needed just for the Akida Exporter.**
MNIST needs one because its `.pt` Data Loader always binds *both* `train_loader` and `test_loader`
regardless of which role you use it for, so an unguarded second `.pt` loader silently clobbers
`test_loader` with validation data. SHD's `tonic_shd` train loader (node 1) already correctly
auto-binds a real, held-out `test_loader` from tonic's own official SHD split — and the
validation-branch Test Loader (node 9) binds only `val_loader`, never touching `test_loader`. So
node 1 alone is what the Akida Exporter scores against, and it's already correct.

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
| Test Loader (node 9) | `data` | Validation Loop | `val_data` |

**Adam Optimiser's `model` output feeds two nodes** — Validation Loop and Akida Exporter, same
pattern as the MNIST guide.

### Placing the Akida Exporter

Same technique as the MNIST guide: tap the **`model`** output dot on the Adam Optimiser node once
(arms it), tap it again to open **Connect to new node**, type `akida`, select **Akida Exporter** —
it arrives already wired. Double-tap it to open the Inspector and confirm its fields.

---

## 3. Pipeline Settings

Toolbar button on the **Training** canvas.

- `Epochs` = **10** (a reasonable starting point — record what you actually used once you have a
  measured result for §7)
- `Batch Size` = **32**
- `Loss Function` = **ce_count**

Only `Epochs` actually drives codegen — the canvas nodes win for batch size and loss. Set the
other two anyway so the dialog doesn't silently disagree with the canvas.

---

## 4. Canvas: Eval

| # | Node | Fields to set |
|---|---|---|
| 1 | **Test Loader** | `Format` = **tonic_shd**; `Batch Size` = **32**; `Shuffle` = **off**; `Time Window (ms)` = **4** |
| 2 | **State Reset** | none |
| 3 | **Forward Pass** | none |
| 4 | **Accuracy** | `Top-K` = **1** (already default) |

### Wiring

| From | port | To | port |
|---|---|---|---|
| Test Loader | `data` | Forward Pass | `input` |
| Test Loader | `labels` | Accuracy | `labels` |
| State Reset | `model` | Forward Pass | `model` |
| Forward Pass | `spikes` | Accuracy | `spikes` |

---

## 5. Generate, then read three lines before running

Go to Step 5 (Jupyter Lab) and generate. Check these in the notebook before running anything:

1. **Dataset cell** contains `tonic.datasets.SHD`, a `ToFrame` transform, and `PadTensors`.
2. **Architecture cell** builds a `Net` with two `snn.Leaky`/`LIF` layers sized 128 and 20.
3. **Train cell**'s loss call is `loss_fn(spk_out, targets)`, and prints both a training dataset
   line (`SHD: N train / M test samples`) and a separate validation-event line — if you only ever
   see one `.pt`/dataset line before the validation line, something clobbered a loader; re-check
   the wiring in §2.

Run Train before Eval — they share one kernel and Eval inherits `num_steps` from it.

---

## 6. Run

Step 6 (Results), or run the cells in Jupyter. With both platforms ticked you get two tabs: expect
**snnTorch green** and **Akida grey** (generated but deliberately not run — hover the tab for why).

---

## 7. What you should see

**Not yet measured.** This is a new topology (the cochlea stage is removed relative to the
existing, already-run `shd_digit_classifier` walkthrough), so its numbers don't transfer. Record
here after a verified run:

| epoch | train loss | val accuracy |
|---|---|---|
| … | … | … |

**Test accuracy: TBD.** **Akida accuracy (from the Exporter's printed line): TBD.**

---

## 8. Converting your trained model to Akida

Same mechanics as [GUIDE-mnist-fcn-studio.md §10](../2026-07-28/GUIDE-mnist-fcn-studio.md). The
**Akida Exporter** node placed in §2 runs once after the last epoch, reloads `best_model.pt`,
quantizes the trained weights into a real `akida.Model`, evaluates it (in the Akida **software
simulator**, no card needed) against `test_loader`, and prints:

```
snnTorch accuracy : ...
Akida accuracy    : ...
Conversion delta  : ... pp
Deploy bundle     : model.akida-bundle.zip (2000 samples, sha256 ...)
```

Alongside `model.fbz` it writes `model.akida-bundle.zip` — the only artifact any deploy control in
Studio looks for.

**Constraints for a model that can reach real hardware**: a straight chain, LIF neurons, ≤256
neurons per layer, no branching or recurrence. This network (700 → 128 → 20) satisfies all four —
confirmed by the `test_guide_shd_topology_is_exportable` contract test.

### Running it on the physical card

1. Go to the **Results** step and choose **Deploy to Hardware**.
2. In **Deploy to** pick **Akida**.
3. Select your paired host (or pair one from the panel directly).
4. Choose **Use Latest Bundle** — it finds the newest `*.akida-bundle.zip` your pipeline just wrote
   and submits it.
5. Progress runs through validation → loading → mapping → evaluation, measured **on the card**.
6. Enter a **Sample index** and choose **Run Model Sample** to run one recording on the silicon.

Same gates as MNIST: only a near-chance result (below 20%) fails the job; **Run Model Sample**
stays disabled until the job is hardware-verified; re-running with identical data/weights returns
the previous deduplicated job rather than a fresh one.

---

## 9. Benchmarking with Neurobench

1. Build the network as instructed in §1 (or load the `shd_digit_classifier_akida` template).
2. Open the **Neurobench** panel in CNL Studio.
3. In the **Benchmark** dropdown, select the SHD benchmark entry (if present) or use **Custom**
   with this spec.
4. In the **Target** dropdown, select **Akida**.
5. Click **Run Benchmark**.

**Note:** the Neurobench panel currently evaluates the raw CNL specification — it measures the
network with **untrained** weights, useful for hardware-mapping efficiency and power profiles, not
for trained accuracy. For trained accuracy, deploy `model.akida-bundle.zip` through the Akida
Runtime panel as described in §8.
