# Deploying the KWS network to BrainChip Akida

Extends `WALKTHROUGH.md` step 7 (hardware export) for the BrainChip Akida target
specifically. Every step below is a click in the NeuroStudio app — no curl,
no manual Python, no separate scripts.

## What's actually supported today

Akida had four separate, non-integrated code paths in this repo before this
guide and none of them was `neurocnl/neurocnl/export/akida_exporter.py` — the
same shape `loihi`/`spinnaker2`/`sinabs` already have. That gap is now closed
(`neurocnl/neurocnl/export/akida_exporter.py`, `neurocnl/docs/support_matrix.md`).
This new file isn't something you call directly — it's the same mapper
(`neurocnl/neurocnl/mapping/akida_mapper.py`) the app's own Deploy tab already
calls under the hood, now fixed to stop silently dropping each neuron's
`threshold`/`tau`.

**Read this before deploying:** Akida's on-chip activation is a quantized,
fused-into-layer nonlinearity (like a ReLU), not literal spiking
integrate-and-fire. Deploying `keyword_spotting.cnl`'s LIF network to Akida
changes its runtime semantics from spiking to quantized-CNN. The network's
`threshold`/`membrane_time_constant` now survive as `lif_threshold`/
`lif_tau_mem` metadata in the payload the app sends, but nothing on the Akida
side configures the on-chip activation from them yet — flagged as follow-up
work, not done here.

## Requirements

- BrainChip's `akida` SDK only supports **Linux or Windows** — not this Mac.
  The Neurochip backend must be running on a Linux/Windows host with the
  physical AKD1000 board attached — e.g. the existing dev box
  `moosebuntu@192.168.2.51` already used for `make docker-ex-m` deploys.
- `keyword_spotting.cnl`'s topology (`Input → Affine → LIF ×4 → Output`, no
  branching) already satisfies the Deploy tab's "single faithful feed-forward
  chain" requirement — no spec changes needed.

## Steps (all in NeuroStudio)

1. **Design** — Model canvas → paste/load `keyword_spotting.cnl` → **Validate**
   → **Sync to Canvas**.

2. **Train** — go to the **Run** step and click **Start**. This generates and
   executes the training notebook server-side (snnTorch, live epoch/loss
   progress in the sidebar) — no manual notebook execution. When it finishes,
   the trained network is available to the next step automatically.

3. **Deploy to Akida** — go to the **Results** step (bottom action row) →
   **Deploy to Hardware** → select the **Akida** target and your host, then
   click through in order:
   - **Check Readiness**
   - **Map Runtime**
   - **Generate Package** (or **Install** to push straight to the attached
     board, or **Run Inference** once installed)

   This is the real click-path (`akida_workspace.dart`) — it calls neurocnl's
   own `/deploy/akida/network` endpoint, which uses the fixed
   `akida_mapper.py`, so `lif_threshold`/`lif_tau_mem` preservation applies
   automatically with no extra step.

4. **Benchmark** — same **Results** step → **Run Benchmark** button (next to
   Deploy to Hardware) shows the NeuroBench `keyword_spotting` results table
   in-app: accuracy, activation sparsity, synaptic ops, memory.

5. **Energy/latency** — the Akida workspace's readiness/status panel surfaces
   `Neurochip/neurochip/targets/akida.json`-backed power/latency estimates
   alongside the deploy controls.

## Honest caveats (say these on camera, matching `WALKTHROUGH.md`'s style)

- Akida approximates the LIF network as a quantized, fused-activation dense
  network — not a literal spiking simulation on-chip.
- `lif_threshold`/`lif_tau_mem` are preserved in the deploy payload for the
  first time but aren't yet applied to configure Akida's on-chip activation —
  a real gap, tracked as follow-up, not silently glossed over.
- Requires a Linux/Windows host for the real SDK; the app can drive it
  remotely, but verify hardware-path claims on that host, not this Mac.
