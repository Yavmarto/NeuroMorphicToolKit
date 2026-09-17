# Guide: SHD spoken-digit classifier on Akida

**Dataset:** SHD (Spiking Heidelberg Digits) — 700 input channels, 20 spoken-digit classes  
**Topology:** `700 → Linear(128) → LIF → Linear(20) → LIF → 20` with 25 timesteps (`time_window_ms=4`)  
**NMTK path:** Train on **snnTorch** (`works`), export to Akida bundle (`works` in software simulator), deploy to physical card (**needs hardware**).

This is the Akida-ready variant of the SHD classifier. The full-fidelity `shd_digit_classifier` template includes a 700-neuron cochlea stage that **cannot** map to Akida (256 neurons per neural processor max). This guide drops that stage — same tradeoff as MNIST `784→256→10` vs `784→1000→10`.

Gallery shortcut: **SHD Spoken-Digit Classifier (Akida)** (`shd_digit_classifier_akida`).  
CNL source: [`neurocnl/backend/app/templates/shd_digit_classifier_akida.cnl`](../../neurocnl/backend/app/templates/shd_digit_classifier_akida.cnl)

---

## Step map

| Phase | What | Label |
|---|---|---|
| 1–6 | Setup, model, train, eval in NeuroStudio | **works** |
| 7 | Akida Exporter (quantize + software-sim accuracy) | **works** (no card) |
| 8 | Deploy bundle to physical Akida card | **needs hardware** |

---

## Prerequisites

| Requirement | Label | Notes |
|---|---|---|
| Running NMTK backend | **works** | Suite API + jupyter-server healthy |
| SHD dataset | **works** | First notebook run downloads ~125 MB train + ~38 MB test via `tonic.datasets.SHD` |
| snnTorch training | **works** | Only trainable platform for this pipeline |
| Akida SDK (export) | **works** | Runs in the Akida **software simulator** inside the training notebook |
| BrainChip Akida PCIe card | **needs hardware** | Required only for §8 physical inference |
| Paired Akida host | **needs hardware** | Backend must reach `neurochip` native service (port 8002) |

---

## Path A — NeuroStudio (recommended)

### 0. Setup

1. **Setup → Dataset** → **SHD**.
2. **Setup → Target platform** → tick **both** `snnTorch` and **Akida**.
   - `snnTorch` = **Training** badge (runs at Play time).
   - `Akida` = **Deploy only** badge (grey tab at Run; enables Deploy dropdown later).

### 1. Model canvas

| # | Node | Fields |
|---|---|---|
| 1 | **Input** | Size = **700** |
| 2 | **Linear** | Rows = **128**, Cols = **700** |
| 3 | **LIF** | Neurons = **128**, Tau = **0.02**, Threshold = **0.6** |
| 4 | **Linear** | Rows = **20**, Cols = **128** |
| 5 | **LIF** | Neurons = **20**, Tau = **0.03**, Threshold = **0.7** |
| 6 | **Output** | Size = **20** |

Wire: `Input → Linear → LIF → Linear → LIF → Output`.  
**Network Timestep (s)** = **0.001** (empty canvas → Network Settings).

Or load template **SHD Spoken-Digit Classifier (Akida)** — same graph.

### 2. Training canvas

| # | Node | Fields |
|---|---|---|
| 1 | **Data Loader** (train) | `tonic_shd`, batch **32**, shuffle on, `time_window_ms` **4** |
| 2 | **State Reset** | defaults |
| 3 | **Forward Pass** | defaults |
| 4 | **Time Loop** | `Num Steps` = **25** |
| 5 | **CE Count Loss** | replace default MSE loss |
| 6 | **Surrogate Backward** | `fast_sigmoid`, slope **25** |
| 7 | **Adam Optimiser** | lr **0.001** |
| 8 | **Akida Exporter** | defaults (`model.fbz`, 4-bit weights, deploy bundle on) |
| 9 | **Test Loader** (val) | `tonic_shd`, batch 32, shuffle off, `time_window_ms` 4 |
| 10 | **Validation Loop** | save best checkpoint, metric `val_accuracy`, mode max |

Wire Adam `model` → Validation Loop **and** Akida Exporter. Val Test Loader `data` → Validation Loop `val_data`.

**Pipeline Settings:** Epochs = **10** (starting point; increase for better accuracy).

### 3. Eval canvas

| # | Node | Fields |
|---|---|---|
| 1 | **Test Loader** | `tonic_shd`, batch 32, `load_best_checkpoint` **on** |
| 2 | **State Reset** | defaults |
| 3 | **Forward Pass** | defaults |
| 4 | **Accuracy** | Top-K = 1 |

### 4. Generate and run — **works**

1. **Pipeline → Generate** — confirm notebook contains `tonic.datasets.SHD`, two `snn.Leaky` layers (128 + 20), and `loss_fn(spk_out, targets)`.
2. **Run** — snnTorch tab goes green; Akida tab stays grey (deploy-only).
3. First run downloads SHD (~3–8 min depending on network).

**Typical runtime:** ~5–15 min per epoch on GPU; 10 epochs ≈ 1–2 hours.

**Expected training output (example 1-epoch smoke):**

```
SHD: 8156 train / 2264 test samples
epoch 1/1: loss=2.9..., val acc ~5–15% (random init; improves with more epochs)
```

Unlike the recurrent RSNN variant (`cnl.RSynaptic`), this feedforward topology is Akida-exportable. Contract test `test_guide_shd_topology_is_exportable` confirms ≤256 neurons per layer, LIF-only, no recurrence.

---

## 5. Akida export (software simulator) — **works**

After training, the **Akida Exporter** cell prints:

```
snnTorch accuracy : <float>
Akida accuracy    : <float>    # Akida software simulator, not the card
Conversion delta  : <float> pp
Deploy bundle     : model.akida-bundle.zip (2000 samples, sha256 ...)
```

Artifacts:

| File | Purpose |
|---|---|
| `model.fbz` | Quantized Akida model |
| `model.akida-bundle.zip` | Deploy handoff (Studio Deploy step reads this) |
| `best_model.pt` | snnTorch checkpoint |

**No physical card is required** for this step.

---

## 6. Deploy to physical Akida card — **needs hardware**

> **needs hardware** — BrainChip Akida PCIe card, native `neurochip.service`, and a backend that routes port 8002 to the card (not the empty Docker hw-worker stub).

1. **Results → Deploy to Hardware**.
2. **Deploy to** → **Akida**.
3. Select paired Akida host (or pair from the panel).
4. **Use Latest Bundle** → picks `model.akida-bundle.zip` from §5.
5. Wait for validation → loading → mapping → on-card evaluation.
6. **Sample index** + **Run Model Sample** for single-digit inference on silicon.

**Expected on-card output:** Job reaches `hardware_verified`; sample inference returns a digit class 0–19. Near-chance accuracy (<20%) fails the job gate.

**Known hardware failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| Akida target missing in Deploy dropdown | Akida not ticked in Setup | Re-tick **Akida** in Setup → Target platform |
| `503` on Akida routes | Native neurochip service down or Docker worker on 8002 | Use `docker-compose.akida-native.yml` overlay; ensure `neurochip.service` owns 8002 |
| Export OK but deploy fails mapping | Layer >256 neurons or recurrence | Use this guide's 128-neuron hidden layer, not the RSNN variant |
| Run Model Sample disabled | Job not hardware-verified yet | Wait for deploy job completion |

---

## Path B — CLI (generate + train only)

There is no committed `.nmtk` golden path for SHD Akida yet. For headless training of the **recurrent** SHD benchmark (not Akida-deployable), use:

```bash
neuro studio run neurocli/golden_paths/shd_rnn_snntorch.nmtk \
  --api-url http://<your-host>:9000 \
  --epochs 50
```

That RSNN reaches ~10% in 50 epochs on dev (vs ~80% paper baseline) — useful for regression, not Akida deploy. For Akida, use Path A (app) or load `shd_digit_classifier_akida.cnl` into a workspace manually.

---

## Known failure modes (all phases)

| Symptom | Phase | Fix |
|---|---|---|
| `Expected target size [32, 20], got [32]` | Train (RSNN only) | Use this feedforward guide, not `shd_rnn_snntorch.nmtk` |
| Only one dataset line before validation | Generate | Check Training wiring — val loader must not clobber `test_loader` |
| Tonic timestamp overflow warning | Dataset | Pre-existing tonic warning; safe to ignore |
| Akida tab runs and fails | Run | Akida is deploy-only; only snnTorch tab should execute |
| Low accuracy after 10 epochs | Train | Increase epochs to 30–50; SHD is harder than MNIST |

---

## Verification log

| Step | Status | Date |
|---|---|---|
| CNL template + export contract | ✅ `test_guide_shd_topology_is_exportable` | 2026-08-26 |
| `generate-v2` for SHD feedforward | ✅ | 2026-08-26 |
| Akida software-sim export | ✅ (mechanism verified on MNIST; SHD numbers vary by training) | 2026-08-26 |
| Physical card deploy | ✅ on dev rig with native Akida service | 2026-08-14 |
| Measured SHD Akida accuracy table | ⏸ record after your training run | — |

Canvas-level detail: [`current tasks/2026-08-25/GUIDE-shd-akida-studio.md`](../../current%20tasks/2026-08-25/GUIDE-shd-akida-studio.md).
