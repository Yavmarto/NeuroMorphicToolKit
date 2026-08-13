# Guide: a network on the PYNQ-Z2 FPGA from CNL Studio

> **Read this first.** Train → deploy → run works end to end, but **only if your Training canvas has
> a NIR Exporter node** — that node is what carries the learned weights to the board. Without it the
> deploy silently ships an all-zero matrix and the board fires nothing. §0 explains why, and the app
> now says which of the two you are about to do.
>
> Shape of the flow closely mirrors
> [GUIDE-akida-mnist-companion.md](../2026-08-04/GUIDE-akida-mnist-companion.md) (pair a remote
> device over SSH, let the app install its runtime, deploy, run). Where the two are identical this
> guide points there instead of repeating it. Where PYNQ differs — capacity, what an overlay is,
> what "verify" measures — it says so.
>
> For building and training on the Studio canvases, that is
> [GUIDE-mnist-fcn-studio.md](../2026-07-28/GUIDE-mnist-fcn-studio.md). Its MNIST network does
> **not** fit this board; see §1.

Written against the app on **13 August 2026**, after the work in
[pynq-z2-as-real-deploy-target.md](pynq-z2-as-real-deploy-target.md). Every button name below is a
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
the PYNQ workspace and sends it with the deployability check, which reads the single dense matrix out
of it and substitutes it for the spec's zeros.

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

**Mismatch is caught, not guessed.** The trained matrix has to match the network you are deploying.
If it does not, the check refuses with both shapes named and points at the usual cause — a
checkpoint from before your last canvas edit. Two same-shaped matrices in one file are also refused
rather than picked between.

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

Overlay-v1 is a **fixed-function** design. The bitstream is synthesised once and shipped with the
backend; it is **not** rebuilt per network, and **no FINN toolchain is involved**. What you deploy
is a weight matrix and thresholds written into a fixed crossbar over MMIO.

The ceiling is hard, from `Neurochip/hardware/pynq_z2/overlay_manifest.json`:

| Limit | Value |
|---|---|
| Neurons (real populations only) | **256** |
| Real populations | **2** |
| Synapses | **15360** |
| Weight format | **int8** only |
| Neuron model | **LIF** only |
| Dense weight matrices | **1** |
| On-chip memory | 512 KB |
| Learning on chip | none |
| Recurrence / lateral inhibition / spatial connectivity | none |

So the only shape that deploys is:

```
input port  →  LIF population A  →  LIF population B  →  output port
                          └── the single weight matrix ──┘
```

Declared I/O ports are **DMA-streamed, not stored** — they cost neither neurons nor synapses. (This
was a bug until 2026-08-13: a 784-wide input port was counted as 784 neurons and rejected every
network outright.)

A network that fits: **32 → 4**, i.e. a 32-neuron population feeding a 4-neuron population through
a 4×32 matrix — 36 neurons, 128 synapses. Comfortable headroom: **128 → 100** is 228 neurons and
12800 synapses.

MNIST does not fit. Neither does anything with a hidden layer beyond two populations. Do not
promise otherwise.

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
6. Choose **Save and test connection** — this saves, then logs in over SSH and reports back. It
   works before the runtime exists and needs no token, so it is the fastest way to confirm address,
   login and credential.

There is no "same machine as backend" checkbox and no service-account field: a PYNQ-Z2 is always a
separate board, and its runtime runs as the SSH user.

### Reading the status dot next to "PYNQ-Z2"

The dot reports **the paired board**, via launcher control preflight — not the backend container,
which can never see a remote board. Hover for the board name, state and reason. Tap it to re-check.

| Dot | Board state | What to do |
|---|---|---|
| Grey | *Unpaired*, *Reachable* | Install the board runtime (§5) |
| Amber | *Runtime Installed*, *Overlay Missing*, *Degraded Optional Capability* | Install the overlay (§5) |
| Blue | *Provisioning* | Wait — a cold install needs 90–100 s |
| Green | *Ready* | Overlay assets present, DMA reachable |
| Red | *Provision Failed*, *Preflight Failed*, *Error* | Read the tooltip; it carries the board's own reason |

A freshly paired board that has no runtime yet reads its stored state rather than a transport error,
so "not provisioned yet" is distinguishable from "board is off".

## 4b. Build and train a network that fits

Everything about the canvases works exactly as in
[GUIDE-mnist-fcn-studio.md](../2026-07-28/GUIDE-mnist-fcn-studio.md) — only the sizes and one extra
node differ, so follow that guide's canvas mechanics and change these:

1. **Model canvas** — build `input port → LIF → Linear → LIF → output port` at sizes that fit §1.
   `32 → 4` is the smallest useful shape; `128 → 100` uses most of the board. Two LIF populations,
   one Linear between them, nothing else: a third population is rejected by the overlay, not by
   Studio.
2. **Training canvas** — build the pipeline as usual and train on **snnTorch**, which is the only
   trainable target. The board does no learning; it runs the finished weights.
3. **Add a NIR Exporter node** to the Training canvas, after training. This is the step the other
   guides do not need, and skipping it is the single way to get a deploy that runs but computes
   nothing (§0). Leave its filename at `model.nir`.
4. **Press Play** and let the pipeline finish. It writes `best_model.pt`, then the NIR Exporter
   reloads that checkpoint, overlays the learned weights onto the graph, and writes `model.nir` into
   the workspace.
5. Re-open the **Deploy** step and confirm the badge under *Network fit* reads **Trained weights**
   and names your Linear node. If it says *Untrained weights*, the exporter did not run.

Because the input port is DMA-streamed rather than stored, a wide input costs you nothing: a
`64 → 128 → 10` network is 138 neurons and one 128×10 matrix, well inside the ceiling.

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
5. **Deploy to board** — loads the bitstream onto the programmable logic, then writes thresholds and
   the quantized int8 weights over MMIO.

**Deploy sends `require_hardware: true`, and the app rejects the result if the board answers from
its software simulator.** That matters: the board agent has a pure-Python fallback whose success
response is identical to silicon in every field except `runtime_mode`. A simulator deploy is
surfaced as an error, not as a green result — so a green result means the FPGA.

### Deploying without training

Hardware bring-up does not need a trained model. With no `model.nir` the deploy carries zeros, which
still exercises the whole chain — overlay load, MMIO writes, DMA round trip, timing — and is the
right way to confirm a new board works before you have anything to run on it. The badge and the
Review step both say the weights are untrained, so it cannot be mistaken for a working model.

## 6. Run it

The execution pane appears once a deploy has succeeded, badged **Loaded on PYNQ-Z2 FPGA**.

1. **Input spike indices** — the indices of input neurons that spiked, e.g. `0, 3, 7`. Commas,
   spaces and newlines all work, so you can paste from a notebook. **Do not leave this empty**: the
   board treats an empty transfer as a DMA underrun.
2. **Timesteps** — how many simulation steps to run. Minimum 1.
3. **Run on board** — streams the spikes in over AXI-DMA and reads the output spikes back.
4. **Verify** — runs five canonical stimulus cases (`single_spike_0`, `single_spike_1`,
   `multi_spike`, `high_index_spike`, `burst`) and reports per-case timing.
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

## 9. Current measured status

| Stage | State |
|---|---|
| Pair board over SSH | works |
| Install board runtime | works (90–100 s cold) |
| Install overlay from the backend | works, no user-supplied files |
| Overlay loads on the Zynq-7000 PL | works |
| Weights + thresholds written over MMIO | works |
| Run spikes, read spikes back over DMA | works, timed |
| Verify | works — liveness and latency only, not accuracy |
| Trained canvas weights on the board | works, **via a NIR Exporter node** (§0) |
| Zero-weight deploy is labelled as such | works — badge in Deploy, explanation in Review |
| Per-class accuracy / benchmark charts | not implemented |
| FINN bitstream compilation | out of scope; overlay-v1 does not need it |

**On-hardware end-to-end has not been run yet** — the dev host needs `make dev-update` first so the
overlay is in the launcher-control image.
