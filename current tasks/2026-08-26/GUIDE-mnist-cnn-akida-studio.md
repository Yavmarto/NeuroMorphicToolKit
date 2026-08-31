# Guide: MNIST CNN classifier in CNLStudio, Akida variant — step by step

**This is the canvas guide.** It builds the network and training pipeline by hand on Studio's
Model, Training and Eval canvases, same as [GUIDE-mnist-fcn-studio.md](../2026-07-28/GUIDE-mnist-fcn-studio.md)
does for the fully-connected MNIST classifier. This variant uses a real Conv2d+pooling stage
instead of a flat Linear layer — the first template to exercise the Akida converter's
Conv2d/AvgPool2d hardware path (see [the live-SDK verification work](../2026-08-26/) that unlocked
this).

Target: `1x28x28 → Conv2d(8, 3x3) → LIF → AvgPool2d(global) → Flatten → Linear(10) → LIF → 10`.

**Why global pooling, and why the pool kernel is exactly (26, 26):** Akida's average pooling is
only ever *global* — it always collapses the whole spatial extent to 1x1, there is no
windowed/strided average pooling on this hardware. A 3x3 valid-padding convolution on a 28x28
input leaves a 26x26 feature map, so the pool kernel has to be (26, 26) to match it exactly; any
smaller kernel is rejected, not silently widened. The dense tail is 8 → 10, far under Akida's
256-neurons-per-NP limit, so unlike the SHD/N-TIDIGITS guides no hardware-fit compromise was
needed here.

Every label below is the exact text in the Studio UI. Fields not listed are left at their
defaults. There is no measured accuracy figure yet — see §7.

Last verified against the code on **26 August 2026**.

---

## 0. Before you start

**You need your own `.pt` files, same as the FCN MNIST guide** — there is no in-app source for
MNIST. The difference from that guide: your `.pt` tensors must be **native 28x28 images**
(shape `(N, 1, 28, 28)` or `(N, 28, 28)`), not pre-flattened to 784 — a Conv2d layer needs the
spatial axes. If you already built `mnist_train.pt`/`mnist_test.pt` for the FCN guide by
flattening to 784, you need a second, unflattened copy for this network.

### Going to the Akida card? Tick it in Setup — yes, always

Same as every other Akida guide: in **Setup → Target platform**, tick **both** `snnTorch` and
**Akida**. `snnTorch` trains; `Akida` is **Deploy only**. There is no `lava_sim` option for this
network — `lava-nc` has no convolution process, so this template is snnTorch/Akida only, unlike
the dense-only templates.

---

## 1. Canvas: Model

Place eight nodes and set these fields.

| # | Node (palette name) | Fields to set |
|---|---|---|
| 1 | **Input** | `Size` = **784**, `Shape (leave blank for flat)` = **1,28,28** |
| 2 | **Conv2d** | `Shape` = **8,1,3,3**, `Fill` = leave as is, `Stride (h,w)` = **1,1**, `Padding (h,w)` = **0,0**, `Dilation (h,w)` = **1,1**, `Groups` = **1**, `Input Height, Width` = **28,28** |
| 3 | **LIF** | `Neurons` = **8**, `Tau` = **0.02**, `Threshold` = **0.5**, `Resistance` = **1.0**, `Leak` = **0.0** |
| 4 | **AvgPool2d** | `Kernel` = **26,26**, `Stride` = **26,26** |
| 5 | **Flatten** | `Start Dim` = **1**, `End Dim` = **-1** (both already default) |
| 6 | **Linear** | `Rows` = **10**, `Cols` = **8**, `Fill` = leave as is |
| 7 | **LIF** | `Neurons` = **10**, `Tau` = **0.03**, `Threshold` = **0.6**, `Resistance` = **1.0**, `Leak` = **0.0** |
| 8 | **Output** | `Size` = **10** |

Wire, `out` → `in` each time:

```
Input → Conv2d → LIF → AvgPool2d → Flatten → Linear → LIF → Output
```

**Pooling comes before the LIF's own connection, but after the conv's LIF in this list — check
the actual edge order carefully.** The wiring that matters is: `Conv2d → AvgPool2d → LIF(8)`, not
`Conv2d → LIF(8) → AvgPool2d`. Akida fuses the conv, its pool, and its neuron into one hardware
layer, and the converter requires the pool to sit directly after the Conv2d node — the LIF that
follows the pool is what closes the fused layer. Getting this order backwards produces a clear
error at conversion time (`"does not directly follow a Conv2d layer"`), not a silent wrong result.

On empty canvas (deselect every node), the property panel shows **Network Settings** — set
**Network Timestep (s)** = **0.001**.

**Shortcut**: this exact network is also a one-click gallery template — **MNIST CNN Classifier
(Akida)** (`mnist_cnn_classifier_akida`, category "Vision"). Loading it sets the Input's shape
correctly even though the Inspector's `Shape` field is new and easy to miss — if in doubt, load
the template and inspect node 1 to see the field set correctly, then compare against your own
build.

**Notes on the values above**

- **`Input`'s `Size` and `Shape` must agree**: the backend only honors `Shape` when its product
  equals `Size` (`1×28×28 = 784`) — this is existing, intentional behavior (the same rule that
  stops a stale `Shape` from silently overriding a `Size` edit elsewhere), not something new to
  this network. Set both, in that order, and leave the mismatch guard for the pre-flight check to
  catch if you get the shape wrong.
- **`Conv2d`'s `Shape` field is `(filters, in_channels, kernel_h, kernel_w)`** — `8,1,3,3` means 8
  output filters, 1 input channel (grayscale), a 3x3 kernel. This is the same convention as
  `Linear`'s `Rows, Cols`, just rank-4 instead of rank-2.
- **`Conv2d`'s `Input Height, Width` field must be set** — it's only read for the first layer
  after Input (as the field's own description says), but this network's Conv2d *is* the first
  layer, so it's required here. Leaving it blank raises a clear error at conversion time rather
  than guessing.
- `Tau`/`Threshold` values are the same starting points the SHD/MNIST-FCN guides already use for
  a first LIF/output stage — not tuned for this specific network yet (see §7).
- `Fill`/weight values are irrelevant on both `Conv2d` and `Linear` — weights are dropped in the
  CNL-text round trip, same as every other template; every layer gets its default init regardless.

---

## 2. Canvas: Training

Same eight-node pattern as the [SHD Akida guide](../2026-08-25/GUIDE-shd-akida-studio.md)'s
Training canvas, with a `.pt`-file Data Loader instead of a `tonic_*` one — follow
[GUIDE-mnist-fcn-studio.md §2](../2026-07-28/GUIDE-mnist-fcn-studio.md) exactly for the Data
Loader / Test Loader / Akida Exporter mechanics (including its **Test Loader clobbering note** —
the `.pt` loader binds both `train_loader` and `test_loader` regardless of role, so you need the
same guarded second loader that guide describes). The one difference: your `.pt` files are the
native-image ones from §0, not the flattened ones.

**Akida Exporter** node fields: same four defaults as every other Akida guide — `Filename`
`model.fbz`, `Weight bits` **4**, `Deploy bundle` **on**, `Eval samples` **2000**.

---

## 3. Pipeline Settings

Toolbar button on the **Training** canvas.

- `Epochs` = **10** (a reasonable starting point — record what you actually used once you have a
  measured result for §7)
- `Batch Size` = **128**
- `Loss Function` = **ce_count** (or whatever your `.pt` pipeline already uses for MNIST — see the
  FCN guide)

---

## 4. Canvas: Eval

Same as [GUIDE-mnist-fcn-studio.md §4](../2026-07-28/GUIDE-mnist-fcn-studio.md) — Test Loader
(native-image `.pt`), State Reset, Forward Pass, Accuracy (`Top-K` = 1).

---

## 5. Generate, then read three lines before running

Go to Step 5 (Jupyter Lab) and generate. Check these in the notebook before running anything:

1. **Architecture cell** builds a `Net` with a real `nn.Conv2d(1, 8, (3, 3), stride=(1, 1),
   padding=(0, 0))`, an `nn.AvgPool2d`, then a `nn.Linear(8, 10)` — not a flattened
   `nn.Linear(784, ...)` first layer.
2. **Forward cell** comment says `Preserve image axes for Conv2d` and does **not** flatten the
   input before the first layer — if you see a `x.flatten(start_dim=...)` before the conv, the
   Data Loader's `.pt` tensors were flattened at save time and need rebuilding per §0.
3. **Train cell** prints a training dataset line and a separate validation-event line, same
   sanity check as every other guide.

Run Train before Eval — they share one kernel.

---

## 6. Run

Step 6 (Results). With both platforms ticked you get two tabs: expect **snnTorch green** and
**Akida grey** (generated but deliberately not run — hover the tab for why).

---

## 7. What you should see

**Not yet measured.** This is a brand-new template — no prior run to carry values over from.
Record here after a verified run:

| epoch | train loss | val accuracy |
|---|---|---|
| … | … | … |

**Test accuracy: TBD.** **Akida accuracy (from the Exporter's printed line): TBD.**

---

## 8. Converting your trained model to Akida

Same mechanics as [GUIDE-mnist-fcn-studio.md §10](../2026-07-28/GUIDE-mnist-fcn-studio.md). The
**Akida Exporter** node quantizes the trained weights into a real `akida.Model` and evaluates it
in the Akida **software simulator** (no card needed), printing the same
`snnTorch accuracy / Akida accuracy / Conversion delta / Deploy bundle` block every other guide's
Exporter prints.

**What's actually new here, and what was checked before this guide was written:** the Conv2d →
AvgPool2d → LIF fusion this network exercises was verified against real `akida==2.19.3` on the
dev backend host before this template was written — not assumed from vendor docs. Specifically
confirmed: the conv kernel weight layout, the `PoolType.Average` enum name, that Akida's average
pooling is *always* global (which is why the pool kernel above is sized to match the conv's full
output extent, not some smaller window), and that a real `InputConvolutional` + `FullyConnected`
model builds from this exact shape profile (28x28x1 in, 8 filters, 3x3 kernel, 10-class dense
tail). What was **not** re-verified: the trained-accuracy number after a real training run — that
still needs a live run, same as every "TBD" in §7.

### Running it on the physical card

Same five steps as the [SHD Akida guide §8](../2026-08-25/GUIDE-shd-akida-studio.md#running-it-on-the-physical-card):
Results → Deploy to Hardware → Akida → pick your paired host → Use Latest Bundle → run.

---

## 9. Benchmarking with Neurobench

Same as [GUIDE-shd-akida-studio.md §9](../2026-08-25/GUIDE-shd-akida-studio.md#9-benchmarking-with-neurobench)
— build the network as in §1 (or load the `mnist_cnn_classifier_akida` template), open Neurobench,
target Akida. Same caveat: the panel evaluates **untrained** weights (hardware-mapping efficiency
and power, not trained accuracy). For trained accuracy, deploy `model.akida-bundle.zip` through
the Akida Runtime panel as in §8.
