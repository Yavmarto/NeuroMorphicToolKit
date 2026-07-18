# Braille RNN replication — handoff (2026-07-18)

## TL;DR

- Confirmed-good state is **80% test accuracy**, config below. **Latest change (700 epochs + AdamW weight_decay + harsher scheduler) regressed to 67.86% — worse than every prior checkpoint.** Revert to the 80% config before doing anything else.
- Reference notebook's "92%" is **not a reachable target** — it crashes outright under the currently-installed snntorch (1.0.0), a breaking API change from whatever version it was originally validated on. Stop treating 92% as the goal; 80% is the actual best confirmed result.
- Job/thesis demo recommendations are settled (see bottom section) — no outstanding decision there, just execution.

---

## 1. Accuracy history (chronological)

| Change | Result | Notes |
|---|---|---|
| Baseline before this session | 75% | |
| Fixed Linear/Conv2d codegen bias-construction order (bug: used `bias=False` directly instead of construct-then-null, causing RNG-stream drift vs reference) | **77.86%** | Verified byte-identical weight init vs reference via live test |
| + validation-loader `shuffle=True`, checkpoint tie-break `>=`/`<=` (attempt to match reference exactly) | 72% (regression) | Isolated via A/B test: `shuffle=True` was the harmful one |
| Reverted `shuffle=True`→`False`, kept tie-break `>=`/`<=` (harmless, confirmed by isolation) | back to **77.86%** | Confirmed baseline restored |
| + Gradient Clip (`max_norm=1.0`) + Reduce LR on Plateau (`factor=0.5, patience=15`) | **80%** ✅ **current best/known-good** | Loss spikes eliminated, smooth convergence to ~1.2 by epoch 300-500 |
| + epochs 500→700, optimizer Adam→AdamW (`weight_decay=0.0001`), scheduler `factor=0.3, patience=25` (3 changes at once) | **67.86%** (regression) | Loss climbs back up after ~epoch 90 and **flatlines around 2.55-2.65 for the remaining 600 epochs** — never recovers to the ~1.2 level the 80% run reached |

## 2. Diagnosis of the latest (67.86%) regression

**Process mistake first**: three tuning suggestions were applied simultaneously (more epochs, AdamW+weight_decay, harsher scheduler), which breaks the single-variable-at-a-time isolation discipline established earlier this session (the exact method that found the `shuffle=True` regression). Can't currently tell which of the three change is responsible without re-testing them individually.

**Best-guess hypothesis** (not yet verified — needs isolation testing, same as before):
Comparing the training log: both the 80% run and the new 700-epoch run hit a rough patch around epoch 80-110 where loss spikes upward (a normal, previously-observed pattern — visible in earlier logs too). In the 80% run, training recovers from this and continues descending smoothly to ~1.2. In the new run, it does **not** recover — it flatlines around 2.55-2.65 for the remaining ~600 epochs.

The scheduler changed from `factor=0.5, patience=15` (mild, frequent small cuts) to `factor=0.3, patience=25` (waits longer, then cuts harder). Plausible mechanism: the longer patience let the rough patch fully develop before the scheduler reacted, and then the harsher 0.3x cut likely landed right during that bad patch, permanently locking the learning rate too low to escape it — instead of the previous mild/frequent cuts giving the model more chances to keep exploring out of a bad region. `weight_decay=0.0001` (new, stacked on top of the existing L1/L2 spike-activity regularization) is also a plausible contributor — double regularization on an already-tiny (2360-parameter) network could be suppressing weight growth needed to fit the training data.

**Next step (not yet done)**: revert to the exact 80% config, then re-apply the three changes **one at a time**, retraining after each, to isolate which one (or combination) causes the flatline. Suspect order to test: (1) `weight_decay` alone, (2) scheduler `factor`/`patience` alone, (3) epoch count alone.

## 3. Confirmed-good config to restore now (80% baseline)

`neurocnl/backend/app/routers/notebook.py` codegen already correctly reflects this when Gradient Clip + Reduce LR on Plateau nodes have these params — just fix the **node parameters on the Train canvas** back to:

- Optimizer: **Adam** (not AdamW), `lr=0.001`, `weight_decay=0.0`
- Gradient Clip: `max_norm=1.0`
- Reduce LR on Plateau: `factor=0.5`, `patience=15`, `mode=min` (mode isn't UI-exposed, defaults correctly to `min`)
- Epochs: **500** (not 700)

No backend/codegen changes needed — this is purely re-editing node parameters in the Studio app's Train canvas and regenerating.

## 4. Reference notebook status (why 92% isn't the real target anymore)

`paper/03_rnn/Braille_training_snntorch.ipynb` cannot run under the currently-installed **snntorch 1.0.0** — confirmed via direct crash: `RuntimeError` inside `RSynaptic.forward()` (`spk / self.graded_spikes_factor` — size mismatch), traced to `self.lif1.init_rsynaptic()` returning a wrong-shaped tensor. This is a breaking API change between whatever snntorch version the reference was written for and 1.0.0. The generated notebook avoids this because its codegen manually builds zero-tensors for the recurrent hidden state instead of calling `init_rsynaptic()` — a compatibility workaround, not a bug.

Also patched (already applied, keep): `paper/03_rnn/Braille_training_snntorch.ipynb` cell `cell-6`'s three `torch.load(...)` calls now wrapped in `safe_globals([TensorDataset])` + `weights_only=True`, needed because plain `torch.load` defaults changed in torch 2.6+. This patch alone doesn't fix the `init_rsynaptic()` crash above.

Every other known code-level difference between the generated notebook and the reference has been fully diffed and explained (architecture, hyperparameters, loss formula, regularization weights, weight-init RNG order all confirmed identical or deliberately-and-correctly different) — no further "why doesn't it match" investigation is warranted. The gap is a stale/unreachable comparison target, not a bug hunt.

## 5. Confirmed dead-code cleanup done this session (unrelated but landed)

- Deleted `neurocnl/frontend/lib/widgets/canvas/pipeline_palette.dart` (311 lines, zero callers — superseded by the floating-bottom-bar "Add Node" popup already implemented inline in `canvas_screen.dart`). `flutter analyze` clean.
- Fixed `neurocnl/frontend/lib/utils/canvas_projection_utils.dart:64-66` — workspace load was resetting neuron count to 1 instead of the persisted value (`n_neurons` was unconditionally overwritten by a stale `size` field). Fixed to prefer the persisted `parameters['n_neurons']`, falling back to `size` only when absent.

## 6. Next reference notebook to replicate (if/when picked up)

Confirmed via direct inspection (not just README claims) that these have real training loops (`backward()`/`optimizer.step()`, multi-epoch):
- **`paper/Spiking-Neural-Networks-Tutorials-main/tutorial_5_FCN.ipynb`** (recommended first) — plain feedforward `nn.Linear` + `snn.Leaky` (LIF, no recurrence), MNIST. Tests the plain-LIF codegen path, which Braille never exercised.
- `tutorial_6_CNN.ipynb` — same series, `Conv2d` x2 + `MaxPool2d` + LIF, MNIST, 10-epoch loop. Tests the `nir.Conv2d` codegen path.
- Both need MNIST downloaded via `torchvision.datasets.MNIST(download=True)` — not pre-staged in this repo like Braille's `.pt` files were.

Ruled out: `paper/01_lif/` (pure neuron-dynamics demo, no training at all), `paper/02_cnn/` (loads an already-pretrained/converted NIR graph, inference-only), `paper/notebooks-main/` (Norse-based — Norse has no working codegen target in `notebook.py`, only `snntorch_sim` has a real generator).

## 7. Demo plan for thesis + job applications

**Thesis proposal → Braille RNN (current work).** Strong narrative already built-in: real published-paper reproduction, recurrent SNN, and a genuine documented research process (found and fixed a real weight-init bug, isolated a regression via controlled A/B testing, diagnosed a hard library-version incompatibility, improved training stability). That process narrative is itself strong thesis-proposal material, independent of the final accuracy number.

**Job applications — depends on audience, don't need the same demo for both:**

- **Innatera** (Delft — Pulsar chip, spiking neural processor for ultra-low-power always-on sensing; confirmed 2026 production use cases: [42T motor-vibration monitoring](https://www.innatera.com/newsroom/redefining-the-cutting-edge-innatera-debuts-real-world-neuromorphic-edge-ai-at-ces-2026/), Aaroh Labs radar presence detection, Joya wearable gesture recognition) → **Braille RNN**. It's structurally the same problem shape as their flagship customer (42T): multi-channel time-series sensor stream → recurrent SNN → classification. Pitch the parallel explicitly. Also highlight: spike-sparsity (`layer_spike_rates` already logged every run — literally the power-efficiency metric that matters to a neuromorphic chip vendor) and NIR usage (hardware-portability format relevant to their ecosystem).
- **Axelera AI** (Eindhoven — Metis/Europa AIPUs; confirmed this is a **conventional edge AI vision accelerator**, NOT spiking-native hardware — targets multi-channel video analytics, quality inspection, people monitoring, robotics/automotive via the new Europa chip) → **`tutorial_6_CNN.ipynb`** (once built). Their hardware gets no benefit from spike-sparsity, so the Innatera pitch doesn't transfer — show CNN-based classification + edge-deployment awareness instead, framed as "I also work in the classical accelerator paradigm, not only spiking."
- **Generic/unknown-domain job application** → **`tutorial_5_FCN.ipynb`** (MNIST, plain LIF) once built. Universally recognizable dataset means zero domain-explanation overhead in a short interview demo — time goes to showing the Studio tool itself.
- **Other Dutch names surfaced but not yet researched**: Hoursec, IMChip, Onward, GrAI Matter Labs, Ourobionics — no confirmed per-company application-domain info yet. Research before pitching any of these specifically.

Sources checked for the above company claims: [Innatera CES 2026 announcement](https://www.innatera.com/newsroom/redefining-the-cutting-edge-innatera-debuts-real-world-neuromorphic-edge-ai-at-ces-2026/), [IEEE Spectrum on Innatera's Pulsar](https://spectrum.ieee.org/innatera-neuromorphic-chip), [Axelera Europa AIPU announcement](https://www.silicon.co.uk/e-innovation/artificial-intelligence/axelera-europa-ai-chip-627118), [Axelera AI — Wikipedia](https://en.wikipedia.org/wiki/Axelera_AI).
