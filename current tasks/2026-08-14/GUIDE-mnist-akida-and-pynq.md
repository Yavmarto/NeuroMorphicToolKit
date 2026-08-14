# Guide — one MNIST model, trained on snnTorch, aimed at both Akida and PYNQ-Z2

**What this covers.** One dataset, one network shape (`784 → 256 → 10`), trained on snnTorch, then
taken as far as each accelerator currently allows. Read §2 before building anything: the two cards
disagree about where the first `Linear` goes, so you build **two canvases**, not one.

**What each leg actually reaches today.**

| Leg | Status |
|---|---|
| Train on snnTorch | Works. This is the only trainable target. |
| Akida AKD1000 | Works end to end. Runs on the card when one is present, otherwise on a virtual device that is labelled as such. |
| PYNQ-Z2 | Works up to **Network fit**. On-board deploy is blocked — see §5. |

Nothing here is aspirational: every claim below was checked against the code, and the two blocked
things are named as blocked.

---

## §0 — Dataset

Three files, each a `torch.utils.data.TensorDataset` of `x` float32 `(N, 784)` and `y` int64 `(N,)`:

| File | Shape | Used for |
|---|---|---|
| `mnist_train.pt` | (9000, 784) | training |
| `mnist_val.pt` | (1000, 784) | validation, best-checkpoint selection |
| `mnist_test.pt` | (2000, 784) | final score |

The shape is `(N, 784)` and deliberately **not** `(N, 1, 28, 28)`: the generated `forward()` takes its
`x.dim() == 2` branch and repeats the same image across all 25 timesteps, which is the rate-coding
input scheme these networks expect.

**Honest gap: there is no in-app way to produce these files.** The only producer is
`current tasks/2026-07-28/prepare_mnist_pt.py`, a developer script run from a terminal with
`uv run`. Worse, `dataset_catalog.py` does not list `.pt` as an importable extension, so the dataset
catalog and *Import local dataset* both reject these files by design. The one route that works is the
**Browse** button on a Data Loader node, which uploads the file directly. If you are following this
guide as an end user and do not have the three files already, this is the step where you need a
developer — that is a gap in the app, not something you are doing wrong.

Once uploaded, the file lives under `pipeline_uploads/` on the server and the node's path turns into a
server path. It stays there between sessions, so this is a one-time cost.

---

## §1 — The shape, and why this one

`784 → 256 → 10`. On a `Linear`, **`Rows` is the output width and `Cols` the input width**, so
784→256 is `Rows = 256, Cols = 784`.

Two matrices: 784×256 and 256×10, which is 203,264 weights. That is the largest MNIST network that
satisfies both accelerators at once:

- **Akida** caps a layer at **256 neurons**, which is what rules out the 1000-unit hidden layer from
  the older MNIST guide.
- **PYNQ-Z2** overlay-v2 allows 1024 neurons per population, 4096 total, 4 populations, 4 matrices
  and 262,144 synapses. `784 → 256 → 10` fits; `784 → 1000 → 10` does not (784,000 synapses).

Do not scale down looking for something smaller — a 10×10 MNIST would not help, since capacity is not
the constraint, and no downscaled MNIST exists in the toolkit anyway.

---

## §2 — Two canvases, differing by one node

This is the part that costs people a day, so it is stated plainly.

**Akida wants the Linear first:**

```
Input → Linear → LIF → Linear → LIF → Output
```

Akida has no layer for "neurons without weights". It fuses each LIF into the `Linear` before it and
uses the LIF as that layer's activation, folding the LIF's threshold into the layer's own variables.
A LIF with no `Linear` ahead of it therefore cannot be mapped, and conversion stops with
*"has no weight layer before it; Akida fuses weights and neurons into one layer."*

**PYNQ wants a LIF first:**

```
Input → LIF → Linear → LIF → Linear → LIF → Output
```

On the board, a `Linear` whose input comes straight from the input port is the fixed DMA path, not a
layer — its weights are never written to the fabric. So every matrix you want on the board must sit
**between two LIF populations**, and there is always one more LIF than Linear.

**The consequence is asymmetric, and this is the trap.** The Akida canvas *passes* PYNQ's Network fit
check, so nothing warns you — but it reports **266 neurons across 2 populations** instead of
**1050 across 3**, because the 784×256 projection is being treated as the DMA path. You would deploy
a network missing its largest matrix. Use the right canvas per target; do not reuse one because the
fit check went green.

The good news: both canvases hold the **same two weight matrices**, so only the input encoding
differs — a full-width LIF that spikes the pixels, versus Akida quantizing them directly.

### Akida canvas — every field

| # | Node | Fields |
|---|---|---|
| 1 | **Input** | `Size` = **784** |
| 2 | **Linear** | `Rows` = **256**, `Cols` = **784**, `Fill` = leave as is |
| 3 | **LIF** | `Neurons` = **256**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta` = **0.95** |
| 4 | **Linear** | `Rows` = **10**, `Cols` = **256**, `Fill` = leave as is |
| 5 | **LIF** | `Neurons` = **10**, same LIF values as row 3 |
| 6 | **Output** | `Size` = **10** |

### PYNQ canvas — every field

| # | Node | Fields |
|---|---|---|
| 1 | **Input** | `Size` = **784** |
| 2 | **LIF** | `Neurons` = **784**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta` = **0.95** |
| 3 | **Linear** | `Rows` = **256**, `Cols` = **784**, `Fill` = leave as is |
| 4 | **LIF** | `Neurons` = **256**, same LIF values as row 2 |
| 5 | **Linear** | `Rows` = **10**, `Cols` = **256**, `Fill` = leave as is |
| 6 | **LIF** | `Neurons` = **10**, same LIF values as row 2 |
| 7 | **Output** | `Size` = **10** |

`Tau = 0.002` with `Time Step = 0.0001` is what makes `Beta` 0.95 — the two agree, so it does not
matter which the generator reads.

### Ready-made workspaces

Both canvases already exist, wired to the uploaded datasets:

- `workspaces/pynq-mnist-784-256-10.nmtk` — PYNQ canvas, with a **NIR Exporter** and no Akida Exporter
- `workspaces/akida-mnist-784-256-10.nmtk` — Akida canvas, with an **Akida Exporter** at `weight_bits` 4

Open one instead of building from scratch. Each validates clean and generates a notebook whose model
is `nn.Linear(784, 256)` then `nn.Linear(256, 10)`.

---

## §3 — Train on snnTorch

The training canvas is the same for both variants. Data Loader (`format` = `pt`, `Batch Size` 128,
shuffle on) → Forward Pass → Time Loop (`num_steps` 25) → MSE Count Loss → Surrogate Backward → Adam
→ Validation Loop, with a Test Loader feeding the Validation Loop for checkpoint selection.

Point the loaders at the right files: **`mnist_val.pt` selects the best checkpoint and `mnist_test.pt`
is the final score.** Do not select checkpoints on the test set — the shipped workspaces have this
the right way round.

**Exporter nodes are not interchangeable.** The PYNQ workspace carries a **NIR Exporter**
(`model.nir`) because the CNL round trip drops weights, so PYNQ reads the trained values back from
that file. The Akida workspace carries an **Akida Exporter** instead. Putting an Akida Exporter on the
PYNQ canvas cannot work — it is the leading full-width LIF that Akida refuses.

Before you hit Play, the app now checks the dataset's feature width against the Input node's `Size`
and refuses with both numbers named if they disagree. If you see a message about "provides 784
features per sample, but the network's input port declares 32", the model is sized for something other
than MNIST — that is §2's table not having been applied.

Expect a falling loss over the configured epochs. `weight_bits` must be 1, 2 or 4: the notebook
generator also accepts 8, but the Akida deploy gate rejects it, so an 8-bit export converts locally
and then fails later.

---

## §4 — Akida leg

Run the Akida Exporter on the **Linear-first** workspace. It writes a `*.akida-bundle.zip` containing
the manifest, `model.fbz` and the evaluation arrays; that bundle is the only interface to the card.

**Read the runtime target, not the accuracy.** Three outcomes exist and they look similar in passing:

| `runtime_target` | Meaning |
|---|---|
| `hardware` | Ran on a physical AKD1000. This is the only real card result. |
| `akd1000_simulator` | The SDK is installed but no card was found; ran on a virtual device. |
| `software_fallback` | No SDK at all; ran on a pure-Python simulator. |

**Hardware verified** is the badge to look for. As of this writing no `runtime_target=hardware` run
has ever been recorded in this repo, so if you get one you are the first — record it. Requesting
hardware when no card is present fails loudly with `PHYSICAL_HARDWARE_REQUIRED` rather than quietly
substituting the simulator, which is the behaviour you want.

---

## §5 — PYNQ-Z2 leg, and where it stops

Works today, no board firmware needed beyond the agent: **pair the board → connectivity test →
install board runtime → Network fit**. Network fit on the PYNQ workspace reports 1050 neurons across
3 populations, which is the signal that both matrices are being counted.

**On-board deploy is blocked, deliberately.** The v2 overlay is written but its bitstream has never
been synthesised, and the only bitstream that exists is v1 — which the launcher refuses by name
because v1's weight memory was never wired to the compute engine and always returned empty output.
Refusing it is correct: a v1 "success" would be silence dressed up as a result. The board therefore
sits at `overlay_missing`, the Deploy button stays disabled, and the v2 manifest additionally ships
with every register offset unresolved.

So: everything up to Network fit is real, and nothing has run on a physical PYNQ board. Do not read a
green fit check as a deployment.

---

## §6 — Developer appendix: building the v2 bitstream

Developer-only, and **not runnable from a Mac** — `build_overlay.sh` refuses to run off Linux. It
needs a Linux x86_64 host with **Vivado 2022.x** and **Vitis HLS** on `PATH`.

1. `Neurochip/hardware/pynq_z2/scripts/build_overlay.sh` — HLS-synthesises the engine, runs Vivado,
   then `sync_manifest_offsets.py --write` to pull the real register offsets out of the produced
   `.hwh`, then `--check` to prove there is no drift.
2. `Neurochip/hardware/pynq_z2/scripts/stage_overlay.sh` — copies `snn_overlay.bit`, `snn_overlay.hwh`
   and the manifest into `Neurochip/overlay_staging/pynq_z2/`.
3. Commit those three files, then rebuild and redeploy launcher-control (its image bakes the staging
   directory in).

Only then does the launcher stop refusing the overlay, and only then is a board result meaningful.
There is no FINN path — this is a fixed-function overlay, and FINN is out of scope for it.

---

## §7 — When something goes wrong

| Symptom | Cause |
|---|---|
| `mat1 and mat2 shapes cannot be multiplied (128x784 and 32x4)` | The model is sized for 32 inputs / 4 classes but the dataset has 784 features. `128` is the batch size and `784` comes from the `.pt` file — neither is in the notebook. Apply §2's table. |
| `has no weight layer before it` on Akida export | The PYNQ canvas was exported to Akida. Use the Linear-first workspace. |
| Akida fit says `exceeds_np_size` | A layer is over 256 neurons — most often the PYNQ canvas's leading 784-wide LIF. |
| Network fit passes but reports 266 neurons | The Akida canvas is aimed at PYNQ; the 784×256 matrix is being read as the DMA path. Use the PYNQ workspace. |
| "The backend has no overlay to install." | Expected — see §5. Not a misconfiguration on your side. |
| A LIF shows 1 neuron on the canvas | Fixed 2026-08-14. Population sizes were looked up case-sensitively, so mixed-case node names never received their inferred size. |

---

## Provenance

Supersedes nothing; complements `current tasks/2026-07-28/GUIDE-mnist-fcn-studio.md` (canvas
mechanics in depth, Akida-oriented) and `current tasks/2026-08-13/GUIDE-pynq-z2-hardware.md` (board
setup, capacity ceilings, overlay status). Written 2026-08-14 alongside the width-guard and
Validate-500 fixes recorded in `current tasks/2026-08-14/mnist-width-mismatch-and-validate-500.md`.
