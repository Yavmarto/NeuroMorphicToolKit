# Guide: a network on the PYNQ-Z2 FPGA from CNL Studio

> **Read §9 first.** Deploying to a physical board is **blocked today, on purpose**: the v2 overlay
> is written but its bitstream has not been built, and the launcher refuses the v1 overlay that is
> still staged, because v1 could never compute. Everything up to and including *Network fit* works,
> and that is the part worth following now.
>
> **Second thing.** Once the board is unblocked, train → deploy → run works only if your Training
> canvas has a **NIR Exporter node** — that node is what carries the learned weights. Without it the
> deploy silently ships an all-zero matrix and the board fires nothing. §0 explains why, and the app
> says which of the two you are about to do.
>
> Shape of the flow closely mirrors
> [GUIDE-akida-mnist-companion.md](../2026-08-04/GUIDE-akida-mnist-companion.md) (pair a remote
> device over SSH, let the app install its runtime, deploy, run). Where the two are identical this
> guide points there instead of repeating it. Where PYNQ differs — capacity, what an overlay is,
> what "verify" measures — it says so.
>
> For building and training on the Studio canvases, that is
> [GUIDE-mnist-fcn-studio.md](../2026-07-28/GUIDE-mnist-fcn-studio.md). Its `784 → 1000 → 10` network
> still does not fit this board; the `784 → 256 → 10` variant it recommends for Akida now does. See
> §1, and §4b for the exact node fields.

Written against the app on **13 August 2026** and revised **14 August 2026** for overlay-v2, after
the work in [pynq-z2-as-real-deploy-target.md](pynq-z2-as-real-deploy-target.md) and
[pynq-overlay-v2-rebuild.md](../2026-08-14/pynq-overlay-v2-rebuild.md). Every button name below is a
label that exists on screen.

## 0. How trained weights reach the board

**The CNL spec does not carry weight values.** It stores tensor *shape* only —
`neurocnl/neurocnl/nir_cnl/renderer.py` says so outright ("CNL only carries tensor shape; exact
tensor payloads belong in NIR/canvas sidecars") and the round-trip contract specifies a zero-filled
recovered tensor. Since the PYNQ payload is built from the spec, a trained network used to deploy
with every weight at 0.0: right shape, right synapse count, no values. It loaded the overlay and
fired nothing.

**The fix is the NIR Exporter node.** It is the only thing in the pipeline that writes learned
values to disk in a form another target can read: it loads `best_model.pt` after training, overlays
the weights onto the NIR graph, and writes `model.nir`. Studio now fetches that file when you open
the PYNQ workspace and sends it with the deployability check, which reads **every** dense matrix out
of it and substitutes them for the spec's zeros — one per layer, in chain order.

So there is exactly one thing to remember:

> **Put a NIR Exporter node on your Training canvas.** No node, no trained weights — and the board
> will run happily while computing nothing.

**The app tells you which you are getting.** Under *Network fit* in the Deploy step there is a badge:

| Badge | Meaning |
|---|---|
| **Trained weights** (green) | The payload carries learned values, and it names the node and matrix they came from |
| **Untrained weights** (amber) | No `model.nir` in the workspace — the deploy would be all zeros |
| **Trained model is empty** (amber) | A `model.nir` matching this network exists but is all zeros; it was exported before training ran |

If a run then produces no spikes, the Review step distinguishes the two cases rather than sending
you to look for a threshold problem that is not there.

**Mismatch is caught, not guessed.** Each trained matrix has to match the layer it lands on. If one
does not, the check refuses naming **which layer**, both shapes, and the usual cause — a checkpoint
from before your last canvas edit. A file holding a different number of matrices than the network has
layers is refused on that count alone.

Layers are matched by **position in the chain**, not by name, because the CNL spec and the NIR graph
disagree about names. That is also what lets a `256 → 256 → 256` network work: two same-shaped
matrices are told apart by where they sit, which shape alone cannot do.

### A note on quantisation

Feeding real weights in exposed a second bug, now fixed: the "is this quantisable?" gate demanded
that every scaled weight land exactly on an integer. That contradicts the `np.round` inside the
quantiser it guarded, and it is a test essentially no trained matrix passes — it had simply never
fired, because PYNQ weights were always zeros or hand-picked literals. int8 quantisation is lossy by
design, so now only genuinely impossible weights are refused (non-finite ones), and a weight that
rounds away to zero produces a warning naming how many did:

```
2 of 128 non-zero weights (1.6%) round to zero at 8-bit precision
and will not fire on the board
```

## 1. What fits — read before you design anything

The overlay is a **fixed-function** design. The bitstream is synthesised once and shipped with the
backend; it is **not** rebuilt per network, and **no FINN toolchain is involved**. What you deploy
is a chain of weight matrices plus per-layer neuron parameters.

The ceiling is hard, from `Neurochip/hardware/pynq_z2/overlay_manifest.json`
(`snn_overlay_v2` / `2.0.0`):

| Limit | Value |
|---|---|
| Neurons per LIF population | **1024** |
| Neurons total (real populations only) | **4096** |
| Real populations | **4** |
| Dense weight matrices | **4** |
| Synapses | **262144** |
| On-chip budget (weights + neuron state) | **320 KB** |
| Weight format | **int8** only |
| Neuron model | **LIF** only |
| Learning on chip | none |
| Recurrence / branching / merging / lateral inhibition / spatial connectivity | none |

**The topology rule, once.** A single unbranched feedforward chain of LIF populations. The engine
walks layer 0, then 1, then 2, handing each layer's spikes to the next, so a branch, a merge, two
disjoint chains, or a cycle has nowhere to go and is rejected. That is what `_is_linear_chain`
([planner.py:465](../../neurocnl/neurocnl/planner.py:465)) enforces.

```
input port  →  LIF A  →  LIF B  →  LIF C  →  output port
                    └ matrix ┘└ matrix ┘        (up to 4 matrices)
```

Declared I/O ports are **DMA-streamed, not stored** — they cost neither neurons nor synapses. (This
was a bug until 2026-08-13: a 784-wide input port was counted as 784 neurons and rejected every
network outright.) A matrix whose source is a declared port is that fixed DMA path, **not** a
layer — which is why every weight matrix you want on the board has to sit between two LIF
populations. §4b's tables are built that way.

Two shapes worth knowing, both spelled out node-by-node in §4b:

- **`32 → 4`** — 36 neurons, 128 synapses. The smallest thing worth deploying; use it for board
  bring-up.
- **`784 → 256 → 10`** — 1050 neurons, 203264 synapses, about 199 KB of the 320 KB budget. MNIST
  scale. This did **not** fit overlay-v1 and does fit v2.

What still does not fit: any population over 1024 neurons, and `784 → 1000 → 10` — its 784000
synapses are three times the weight cache.

## 2. Update the backend

The overlay bitstream ships **inside** the backend image, so the board can be given a bitstream
without you ever opening a terminal or installing Vivado. That also means an out-of-date backend has
no overlay to install.

**End users:** open **Backend Setup** in the NMTK app. If **Backend update available** appears,
choose **Update backend** once. Workspaces, notebooks and credentials are preserved.

**Developers pushing unreleased source to the dev host** — this is the developer path, not something
to hand a user:

```bash
make dev-update
```

That syncs, then rebuilds `launcher-control` (it maps both `Dockerfile.control` and `Neurochip/*` to
a rebuild) so the overlay lands at
`/app/artifacts/neurochip/overlay_staging/pynq_z2/`. Check the plan first with:

```bash
make dev-update ARGS='--dry-run'
```

## 3. Prepare the board

The board needs the stock **PYNQ SD-card image** booted and on the network. Nothing else — the app
installs its own runtime.

1. Note the address the board came up on. The PYNQ image's own start page shows it; `pynq.local`
   usually resolves.
2. You need an SSH login **that can sudo**. The stock image ships `xilinx`, which can.

Same sudo caveat as Akida, and the same silent fallback: without sudo the install still completes,
but into user space rather than systemd, and the runtime then needs a manual restart after an
overlay change. The app tells you when this happens.

## 4. Pair the board in Studio

1. Open **CNL Studio** → **Setup**.
2. Under **Target platform**, add **PYNQ-Z2**.
3. Choose **Manage Targets** (the gear beside PYNQ-Z2), then add a board.
4. Fill in: display name, **board address**, **SSH user** (pre-filled `xilinx`), SSH port, and the
   password or key for that login.
5. Leave **Advanced settings** collapsed. Studio derives the board runtime URL on port 8002. The
   override is only for a nonstandard contract.
6. Choose **Save and test connection** — this saves, then logs in over SSH and reports back
   underneath the form. It works before the runtime exists and needs no token, so it is the fastest
   way to confirm address, login and credential. It does **not** install anything; that is §5.
7. Back on the target list, each board row has a **Test connection** icon (the circular arrow) that
   re-runs the same check without reopening the form.

*(Both controls were missing for PYNQ until 2026-08-14 — the callback that draws them was wired
only for Akida, so a board could be saved but never contacted from anywhere in the app. If you do
not see them, update the backend.)*

There is no "same machine as backend" checkbox and no service-account field: a PYNQ-Z2 is always a
separate board, and its runtime runs as the SSH user.

### Reading the status dot next to "PYNQ-Z2"

The dot reports **the paired board**, via launcher control preflight — not the backend container,
which can never see a remote board. Hover for the board name, state and reason. Tap it to re-check.

| Dot | Board state | What to do |
|---|---|---|
| Grey | *Not checked yet*, *Reachable* | Install the board runtime (§5) |
| Amber | *Runtime Installed*, *Overlay Missing*, *Degraded Optional Capability* | Install the overlay (§5) |
| Blue | *Provisioning* | Wait — a cold install needs 90–100 s |
| Green | *Ready* | Overlay assets present, DMA reachable |
| Red | *Provision Failed*, *Preflight Failed*, *Error* | Read the tooltip; it carries the board's own reason |

A freshly paired board that has no runtime yet reads its stored state rather than a transport error,
so "not provisioned yet" is distinguishable from "board is off". **Tapping the dot on a board
nothing has contacted yet runs the SSH check first**, then re-reads readiness — so the dot can move
from where you paired the board, and the message names the button that clears the state it landed
on. Before 2026-08-14 that state was labelled *Unpaired*, which read as "you have not paired a
board" for a board that was in fact paired, and re-checking could never change it.

## 4b. Build and train a network that fits

Everything about the canvases works exactly as in
[GUIDE-mnist-fcn-studio.md](../2026-07-28/GUIDE-mnist-fcn-studio.md) — only the sizes and one extra
node differ, so follow that guide's canvas mechanics and change what is below.

### 4b.1 The two rules that decide the whole shape

**Rule 1 — a LIF goes first, before any Linear.** The order is
`Input → LIF → Linear → LIF → …`, **not** the MNIST guide's `Input → Linear → LIF → …`.

A Linear whose input comes straight from the Input port is the board's fixed DMA path, not a layer,
so **its weights are dropped and never reach the board**. That is not theoretical — the MNIST guide's
order, at 784 → 256 → 10, deploys 2560 weights instead of 203264 and still reports *exportable*:

| Canvas order | Layers the board gets | Weights deployed |
|---|---|---|
| `Input → Linear → LIF → Linear → LIF → Output` | 1 (`256 → 10` only) | **2560** — the 784×256 matrix is silently lost |
| `Input → LIF → Linear → LIF → Linear → LIF → Output` | 2 (`784 → 256`, `256 → 10`) | **203264** |

So every Linear you want on the board must sit **between two LIF populations**, and the count is
always **one more LIF than Linear**.

**Rule 2 — on a Linear, `Rows` is the LIF after it, `Cols` is the LIF before it.** A 32-neuron layer
feeding a 4-neuron layer is `Rows = 4, Cols = 32`. Backwards, and the fit check refuses with both
shapes named.

`Fill` on a Linear is irrelevant — weights are dropped in the CNL round trip and arrive from
`model.nir` instead (§0).

### 4b.2 Model canvas — every field, both shapes

Place the nodes in the order listed and wire `out` → `in` straight down, no branches. Every field
each node has is listed; nothing is left to another document. The LIF values are identical on every
LIF in both shapes — only `Neurons` changes.

**Smallest useful shape — `32 → 4`.** Two LIF populations, one Linear. 36 neurons, 128 synapses.
Use this for board bring-up.

> **This shape is not for MNIST.** It takes 32 features and emits 4 classes, so the
> `mnist_train.pt` / `mnist_val.pt` / `mnist_test.pt` files — which are `(N, 784)` with 10 classes
> — do not fit it, and no reduced 32-feature MNIST exists. Wiring them here trains until the first
> `Linear` and then stops with a width mismatch. There is no dataset in the toolkit that matches
> `32 → 4`; build it only to bring a board up, with no Data Loader attached. For anything trained on
> MNIST use the `784 → 256 → 10` table below.

| # | Node (palette name) | Fields to set |
|---|---|---|
| 1 | **Input** | `Size` = **32** |
| 2 | **LIF** | `Neurons` = **32**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta (mem decay)` = **0.95** |
| 3 | **Linear** | `Rows` = **4**, `Cols` = **32**, `Fill` = leave as is |
| 4 | **LIF** | `Neurons` = **4**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta (mem decay)` = **0.95** |
| 5 | **Output** | `Size` = **4** |

**MNIST scale — `784 → 256 → 10`.** Three LIF populations, two Linears. 1050 neurons,
203264 synapses, 203.63 KB of the 320 KB budget.

| # | Node (palette name) | Fields to set |
|---|---|---|
| 1 | **Input** | `Size` = **784** |
| 2 | **LIF** | `Neurons` = **784**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta (mem decay)` = **0.95** |
| 3 | **Linear** | `Rows` = **256**, `Cols` = **784**, `Fill` = leave as is |
| 4 | **LIF** | `Neurons` = **256**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta (mem decay)` = **0.95** |
| 5 | **Linear** | `Rows` = **10**, `Cols` = **256**, `Fill` = leave as is |
| 6 | **LIF** | `Neurons` = **10**, `Tau` = **0.002**, `Threshold` = **1.0**, `Resistance` = **1.0**, `Leak` = **0.0**, `Time Step` = **0.0001**, `Beta (mem decay)` = **0.95** |
| 7 | **Output** | `Size` = **10** |

`Tau = 0.002` with `Time Step = 0.0001` is what makes `Beta` 0.95 — the two agree, so it cannot
matter which one the generator reads. `Tau` is also what the board maps onto its leak shift.

**Do not use `cnl.Leaky` instead of `LIF`** — same trap as the MNIST guide's §1: it emits kind
`leaky_explicit`, which switches the generated `forward()` to a per-timestep loop variable and
crashes on static input.

**Check your counts before leaving the canvas.** The numbers in each shape's name are the LIF
`Neurons` values, in order. `32 → 4` means two LIFs; `784 → 256 → 10` means three. If you have as
many LIFs as Linears, you have the MNIST order and your first matrix will not reach the board.

### 4b.3 Train it

1. **Training canvas** — build the pipeline as usual and train on **snnTorch**, which is the only
   trainable target. The board does no learning; it runs the finished weights.
2. **Add a NIR Exporter node** to the Training canvas, after training. This is the step the other
   guides do not need, and skipping it is the single way to get a deploy that runs but computes
   nothing (§0). Leave its filename at `model.nir`.
3. **Press Play** and let the pipeline finish. It writes `best_model.pt`, then the NIR Exporter
   reloads that checkpoint, overlays the learned weights onto the graph, and writes `model.nir` into
   the workspace.
4. Re-open the **Deploy** step and confirm the badge under *Network fit* reads **Trained weights**
   and names your Linear node. If it says *Untrained weights*, the exporter did not run.

## 5. Bring the board up, then deploy

Go to the **Deploy** step and choose **PYNQ-Z2**. The workspace has board setup on the left and
execution on the right. Setup offers **only the step the board is actually blocked on**, so work top
to bottom:

1. **Install board runtime** — SSHes in, builds a venv, installs the agent, and starts it under
   systemd (or user space without sudo). Two minutes cold. The pane reports progress; it is not hung.
2. **Install overlay** — copies `snn_overlay.bit`, `snn_overlay.hwh` and `overlay_manifest.json`
   from the backend to the board over SCP. **You supply nothing.** If this reports that the backend
   has no overlay, that is a broken or outdated backend install, not a missing step on your side —
   the pane lists exactly which files are absent.
3. **Check readiness** — asks the board's own runtime whether the overlay assets and DMA are usable.
   You want *Ready*.
4. **Network fit** — the card below shows the overlay verdict for whatever spec is open, with the
   neuron and synapse counts it actually gated on. Fix rejections here before deploying; the payload
   is only built for a network that fits.
5. **Deploy to board** — loads the bitstream onto the programmable logic, then hands the engine its
   quantized int8 weights and per-layer parameters in DDR. (Overlay-v1 wrote weights over MMIO to an
   address the fabric did not map, which is why it never computed; v2's weights travel over an AXI
   master instead, and that is what lifted the synapse ceiling.)

**Deploy sends `require_hardware: true`, and the app rejects the result if the board answers from
its software simulator.** That matters: the board agent has a pure-Python fallback whose success
response is identical to silicon in every field except `runtime_mode`. A simulator deploy is
surfaced as an error, not as a green result — so a green result means the FPGA.

### Deploying without training

Hardware bring-up does not need a trained model. With no `model.nir` the deploy carries zeros, which
still exercises the whole chain — overlay load, weight transfer, DMA round trip, timing — and is the
right way to confirm a new board works before you have anything to run on it. The badge and the
Review step both say the weights are untrained, so it cannot be mistaken for a working model.

## 6. Run it

The execution pane appears once a deploy has succeeded, badged **Loaded on PYNQ-Z2 FPGA**.

1. **Input neurons that spike** — which input neurons fire, e.g. `0, 3, 7`. Commas, spaces and
   newlines all work, so you can paste from a notebook. The helper text under the field names the
   valid range for the network you deployed. **Do not leave this empty**: an all-silent frame is a
   DMA underrun on the board.

   Each neuron you name spikes on **every** timestep — the same static-input scheme the trained
   snnTorch network was evaluated under, where one image is presented repeatedly. The app expands
   your list into what the overlay consumes, which is one word per input neuron per timestep. You
   never type that; it is only worth knowing because a run of 3 named neurons over 25 timesteps
   moves 784 × 25 words, not 3.
2. **Timesteps** — how many simulation steps to run. Minimum 1.
3. **Run on board** — streams the frames in over AXI-DMA and reads the output back. The result is
   one word per output neuron per timestep, 1 where that neuron spiked.
4. **Verify** — runs five canonical stimulus cases (`silent`, `first_neuron`, `last_neuron`,
   `all_neurons`, `burst`), generated from your network's own input width, and reports per-case
   timing.
5. **Redeploy** — rewrite the network without reloading anything else. Needed after any spec or
   bit-width change; the app clears the old result rather than letting it look current.

**What Verify actually measures.** The default cases carry **no expected output**, so every case
passes as long as the round trip completes. It is a liveness-and-latency check — "the overlay
responds, and here is how long a DMA round trip takes" — **not** an accuracy check. Do not read a
green Verify as proof the network computes correctly.

## 7. Reading the results

**Review** shows three blocks:

- **PYNQ-Z2 Deployability** — the verdict card, kept because it is the context for everything else:
  a network that only just fitted explains a lot about what the board did.
- **Board run** — status, timesteps, output spike count, execution time, and which output neurons
  fired. Timings render as µs below 1 ms and ms above, because a Z2 DMA round trip runs into the
  thousands of microseconds.
- **Verification** — pass count, mean and slowest case, and per-case detail.

Above them sits the provenance badge. It reads the deploy's `runtime_mode`, so it is the single
place the hardware claim is made.

**No output neurons fired?** With zero weights (§0) that is the expected outcome. With real weights
it usually means the input was too sparse, or the threshold too high once the weights were scaled
into int8.

## 8. In-app recovery

| Symptom | What it means | Fix in the app |
|---|---|---|
| Dot amber, *Overlay Missing* | Runtime is up, no bitstream on the board | **Install overlay** |
| Install overlay says the backend has no overlay | Backend image predates the shipped overlay, or is broken | Update the backend (§2) |
| Deploy errors with a simulator `runtime_mode` | Board not powered, or overlay never loaded | Check power, then **Install overlay** → **Check readiness** |
| *Degraded Optional Capability* after an overlay install | User-space install; the agent could not restart itself | **Restart runtime**, or power-cycle the board |
| Run errors "Overlay not deployed" | The agent restarted since the deploy | **Redeploy** |
| Badge reads *Untrained weights* | No `model.nir` in the workspace | Add a NIR Exporter node to the Training canvas, press Play, return here |
| Check refuses with two shapes named | The checkpoint predates your last canvas edit | Re-run training, then redeploy |
| Board unreachable after being fine | Agent died or the board rebooted | **Restart runtime**, then **Check readiness** |
| Install overlay refuses the board's existing overlay by name | The board still has overlay-v1, which cannot compute (§9) | **Install overlay** again once the backend carries v2 |
| Dot grey, *Not checked yet*, after pairing | Nothing has contacted the board yet | Tap the dot — it runs the SSH check — then **Install board runtime** |

## 9. Current status — read this before believing a board result

**The v2 overlay is written but not built.** Everything above the FPGA boundary is source-complete
and green in tests; the bitstream itself has not been synthesised, and the overlay staged in the
backend is still v1. The launcher now **refuses a v1 board by name**, deliberately, because v1 could
never produce a correct result on silicon: its weights were written to an address the fabric did not
map, so every weight read as zero and the board returned silence that the app displayed as a
successful hardware run. Five further defects sat behind that one. See
[pynq-overlay-v2-rebuild.md](../2026-08-14/pynq-overlay-v2-rebuild.md).

So **deploy to a board is blocked today**, on purpose. Everything up to and including *Network fit*
works.

| Stage | State |
|---|---|
| Pair board over SSH, test the connection from the app | works |
| Install board runtime | works (90–100 s cold) |
| Install overlay from the backend | works, no user-supplied files — **but the staged overlay is v1 and is refused** |
| Overlay loads on the Zynq-7000 PL | worked for v1; unverified for v2 |
| Weights reach the engine and it computes | **never worked on v1**; v2 is written, tested on a host compiler, not yet on silicon |
| Run frames, read spikes back over DMA | v2 protocol written both sides and cross-checked against the simulator; not yet on silicon |
| Verify | works — liveness and latency only, not accuracy |
| Trained canvas weights in the payload | works, **via a NIR Exporter node** (§0) |
| Zero-weight deploy is labelled as such | works — badge in Deploy, explanation in Review |
| On-silicon self-test (a deploy that returns zeros fails loudly) | not implemented |
| Per-class accuracy / benchmark charts | not implemented |
| FINN bitstream compilation | out of scope; a fixed-function overlay does not need it |

**Nothing has run on a physical board.** Unblocking it is a developer task on the Linux Vivado host
(§2's developer path), not something a user can or should do: build the v2 bitstream, stage it, then
rebuild the launcher-control image so the app can install it.
