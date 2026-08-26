# Guide: N-TIDIGITS spoken-digit classifier in CNLStudio — step by step

**This is the canvas guide.** Same structure as
[GUIDE-shd-akida-studio.md](GUIDE-shd-akida-studio.md), for a different, smaller multivariate
spike-timeseries dataset: **N-TIDIGITS18**, 64 silicon-cochlea channels, 11 single-spoken-digit
classes (`o, 1-9, z`).

Target: `64 → Linear(64) → LIF → Linear(11) → LIF → 11`, 25 timesteps (padded via tonic's
`ToFrame`, `time_window_ms=4`).

**Unlike SHD, this network needs no separate "Akida variant."** SHD's 700 input channels forced
dropping a 700-wide encoding stage to fit under Akida's 256-neurons-per-NP limit. N-TIDIGITS is
only 64 channels — the whole network, unmodified, is already well under that limit. One template
covers the simulator and the card.

**This dataset format did not exist in Studio before this change** — building it required adding
`tonic_ntidigits` as a real Data Loader format (it wasn't just a matter of picking a dataset).
Load the SHD guide's §0 for the general Akida/Setup pattern; this guide covers what's specific to
N-TIDIGITS.

Last verified against the code on **26 August 2026**. There is no measured accuracy figure yet —
see §7.

---

## 0. Before you start

Same as SHD: no `.pt` file wrangling. In **Setup → Dataset**, select **N-TIDIGITS**. The generated
notebook downloads the real archive itself via `tonic.datasets.NTIDIGITS18` on first run.

**The one real gotcha**: N-TIDIGITS18's raw data is a *connected-digit-sequence* task by default
(e.g. one recording labeled `"6-9-3"`), not single-digit classification. The Data Loader's
`tonic_ntidigits` format always requests `single_digits=True` under the hood, which is what makes
`train_ds`/`test_ds` return one integer class per sample (`class_map`: `o→0, 1-9→1-9, z→10`)
instead of a raw sequence string — this is baked into the codegen, not something you configure.

Setup → Target platform: tick **both** `snnTorch` and **Akida**, same reasoning as SHD/MNIST.

---

## 1. Canvas: Model

Place six nodes and set these fields.

| # | Node (palette name) | Fields to set |
|---|---|---|
| 1 | **Input** | `Size` = **64** |
| 2 | **Linear** | `Rows` = **64**, `Cols` = **64**, `Fill` = leave as is |
| 3 | **LIF** | `Neurons` = **64**, `Tau` = **0.02**, `Threshold` = **0.6**, `Resistance` = **1.0**, `Leak` = **0.0** |
| 4 | **Linear** | `Rows` = **11**, `Cols` = **64**, `Fill` = leave as is |
| 5 | **LIF** | `Neurons` = **11**, `Tau` = **0.03**, `Threshold` = **0.7**, `Resistance` = **1.0**, `Leak` = **0.0** |
| 6 | **Output** | `Size` = **11** |

Wire, `out` → `in` each time:

```
Input → Linear → LIF → Linear → LIF → Output
```

On empty canvas, set **Network Settings → Network Timestep (s)** = **0.001**.

**Shortcut**: this exact network is also a one-click gallery template — **N-TIDIGITS Spoken-Digit
Classifier** (`ntidigits_digit_classifier`, category "Signal Processing").

**Notes on the values above**

- `Tau`/`Threshold` values are carried over unchanged from SHD's own already-validated `hidden`/
  `classes` populations — the same general "LIF classifier chain" starting point, not
  N-TIDIGITS-specific tuning (there's no prior run to tune against yet).
- Hidden width (64) matches the input width, a reasonable capacity choice, not a hard requirement
  — anything up to 256 stays Akida-safe.

---

## 2. Canvas: Training

| # | Node | Fields to set |
|---|---|---|
| 1 | **Data Loader** (train) | `Format` = **tonic_ntidigits**; `Batch Size` = **32**; `Shuffle` = **on**; `Time Window (ms)` = **4** |
| 2 | **State Reset** | none |
| 3 | **Forward Pass** | none |
| 4 | **Time Loop** | `Num Steps` = **25** (default) |
| 5 | **CE Count Loss** | replace the default `mseCountLoss` node with this one |
| 6 | **Surrogate Backward** | `Function` = **fast_sigmoid**, `Slope` = **25** (default) |
| 7 | **Adam Optimiser** | `Learning Rate` = **0.001**; `Weight Decay` 0.0, `Beta 1` 0.9, `Beta 2` 0.999 (default) |
| 8 | **Akida Exporter** | defaults — `Filename` `model.fbz`, `Weight bits` **4**, `Deploy bundle` **on**, `Eval samples` **2000** |

Validation branch:

| # | Node | Fields to set |
|---|---|---|
| 9 | **Test Loader** | `Format` = **tonic_ntidigits**; `Batch Size` = **32**; `Shuffle` = **off**; `Time Window (ms)` = **4** — wire `data` → **Validation Loop**'s `val_data` |
| 10 | **Validation Loop** | `Validate Every N Epochs` **1**, `Save Best Checkpoint` **on**, `Checkpoint Metric` `val_accuracy`, `Checkpoint Mode` `max` (default) |

Same reasoning as SHD: no extra Test Loader node is needed just for the Akida Exporter — node 1's
`tonic_ntidigits` loader already binds a correct `test_loader` from N-TIDIGITS18's own train/test
split, and the validation-branch loader (node 9) binds only `val_loader`.

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

Place the Akida Exporter the same way as SHD/MNIST: tap the Adam Optimiser's `model` output dot
twice, search `akida`, select **Akida Exporter** — arrives already wired.

---

## 3. Pipeline Settings

- `Epochs` = **10** (starting point — record what you actually used once you have a §7 result)
- `Batch Size` = **32**
- `Loss Function` = **ce_count**

---

## 4. Canvas: Eval

| # | Node | Fields to set |
|---|---|---|
| 1 | **Test Loader** | `Format` = **tonic_ntidigits**; `Batch Size` = **32**; `Shuffle` = **off**; `Time Window (ms)` = **4** |
| 2 | **State Reset** | none |
| 3 | **Forward Pass** | none |
| 4 | **Accuracy** | `Top-K` = **1** (default) |

### Wiring

| From | port | To | port |
|---|---|---|---|
| Test Loader | `data` | Forward Pass | `input` |
| Test Loader | `labels` | Accuracy | `labels` |
| State Reset | `model` | Forward Pass | `model` |
| Forward Pass | `spikes` | Accuracy | `spikes` |

---

## 5. Generate, then read three lines before running

1. **Dataset cell** contains `tonic.datasets.NTIDIGITS18`, a `ToFrame` transform, `PadTensors`, and
   `single_digits=True` on both `train_ds`/`test_ds` constructors. If `single_digits=True` is
   missing, labels will be raw sequence strings and training will fail on the loss call — that
   means the Format field wasn't actually set to `tonic_ntidigits`.
2. **Architecture cell** builds a `Net` with two LIF layers sized 64 and 11.
3. **Train cell** prints a training dataset line and a separate validation-event line.

Run Train before Eval — they share one kernel.

---

## 6. Run

Same as SHD: expect **snnTorch green**, **Akida grey** (generated, deliberately not run).

---

## 7. What you should see

**Not yet measured** — record after a verified run:

| epoch | train loss | val accuracy |
|---|---|---|
| … | … | … |

**Test accuracy: TBD.** **Akida accuracy (from the Exporter's printed line): TBD.**

---

## 8. Converting your trained model to Akida

Same mechanics as SHD (§8 of [GUIDE-shd-akida-studio.md](GUIDE-shd-akida-studio.md)) and MNIST.
The Akida Exporter node prints `snnTorch accuracy`, `Akida accuracy`, `Conversion delta`, and
writes `model.akida-bundle.zip`. This network (64 → 64 → 11) is a straight LIF chain, well under
256 neurons per layer — confirmed by the `test_guide_ntidigits_topology_is_exportable` contract
test, no rejections expected.

### Running it on the physical card

Same steps as SHD §8: Deploy to Hardware → Akida → pick paired host → Use Latest Bundle → run.

---

## 9. Benchmarking with Neurobench

Same pattern as SHD §9 / MNIST §11: Benchmark panel → target **Akida** → Run Benchmark. Note the
same caveat — it evaluates untrained CNL weights, not the trained bundle.
