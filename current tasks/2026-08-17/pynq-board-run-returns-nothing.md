# "It deploys, but the results show nothing"

**Symptom.** A successful deploy, then a Board run reporting `success`, `Output spikes 10`,
`Spiking output neurons 0, 0, 0, 0, 0, 0, 0, 0, 0, 0`. The Deploy pane also sat on
"Checking pynq z2." with Deploy greyed out, and read "Overlay: Not installed" beside
"Overlay ready on the FPGA".

Four separate things were wrong. Three are fixed. The fourth is upstream of all of them and is
**not** fixed — it is stated at the end with the measurement that proves it.

## 1. The run was reported as if a full-length frame were a spike count — fixed

Overlay-v2 answers with one word per output neuron per timestep, 1 for a spike. The Review step
reported that stream's *length* as "Output spikes" and printed it verbatim under "Spiking output
neurons", so a silent run read as ten spikes followed by ten zeros — and the message written for
exactly that case never rendered, because an all-zero frame is not an empty list.

Now: total spikes (the sum), spikes per output neuron, the predicted class as the argmax of those
counts, and — when the run used a labelled sample — whether that matches the label.
[pynq_results_view.dart](../../neurocnl/frontend/lib/screens/studio/deploy/pynq_results_view.dart).

`PynqRunResult` also carries two fields the board already sent and the app dropped
([pynq_deployment_model.dart](../../nmtk_ui_core/lib/models/pynq_deployment_model.dart)):
`output_neurons`, without which the stream cannot be split into frames, and
`kernel_reported_done`, which is `false` when the engine never asserted `ap_done` — a run that
still comes back `status: success`. That now shows as a warning on the result.

## 2. There was no way to feed the board a real digit — fixed

The only stimulus was a list of spike indices, defaulting to `0`. The reported run therefore
stimulated one pixel of a 784-pixel image, and nothing firing was the correct answer to it.

New `GET /api/neurocnl/notebook/artifacts/dataset-sample?workspace_folder=…&index=…`
([notebook.py](../../neurocnl/backend/app/routers/notebook.py)) serves one evaluation sample from
the workspace as a 0/1 input frame plus its label, reusing `_discover_workspace_artifact` (given a
`name_prefix` so `eval_*.pt` wins over `best_model.pt`) and a new `pt_dense_tensors` split out of
`dataset_loader._load_pt_dataset`. Decoded tensors are cached per workspace for 60 s so stepping
the index does not refetch megabytes.

The Deploy pane has a sample picker — index stepper, true label, a 28x28 preview of the binarised
frame — with the manual index field behind a toggle. Loading a sample sets the presentation window
to 25 timesteps, which is `num_steps` in the generated training notebook, unless the user typed
their own.

## 3. Two defects in the CNL → board handoff — fixed

[neurochip_pynq_handoff.py](../../neurocnl/neurocnl/handoff/neurochip_pynq_handoff.py)

- **The threshold was scaled twice.** `quantise_network_dict` already scales every population
  threshold by the same factor as the weights; `build_pynq_deploy_payload` scaled it again,
  squaring it. For this MNIST network that is a threshold of **4,129,161** against an accumulator
  that saturates at 784 x 127 = **99,568**. No input could fire a neuron, on any board.
- **The leak was read from the wrong timestep, and from a key nothing writes.** The exporter
  writes `tau_rc`; the handoff read only `tau_m`/`tau`, so every network reached the board with
  `leak_shift: 0` — no leak at all. And the timestep used was the overlay's 1 ms wall-clock step,
  where the model is trained under `snntorch.import_nir`'s hardcoded 0.1 ms. Now the leak comes
  from the training timestep, and `hardware_threshold` retunes the threshold by `2**shift` so the
  static-input firing condition survives the fabric's shift-quantised decay (it can only be
  `1 - 2**-s`).

For this network the payload went from `threshold 4,129,161 / leak_shift 0` to
`threshold 32,512 / leak_shift 4`.

## 4. The trained network emits no spikes at all — NOT fixed

With all of the above in place, five real digits over 25 timesteps still came back silent from the
board. That is faithful: **the model itself does not spike.** Run in numpy against its own
evaluation set, with no hardware and no quantisation involved:

```
greyscale input, 200 samples: 0 correct, 200 silent
total spikes lif1/lif2/lif3: [0, 0, 0]
```

Why: the generated notebook builds every LIF as
`snn.Leaky(beta=0.950000, threshold=20.0000, reset_mechanism='zero', ...)`. Those numbers come from
the CNL spec's `time constant 0.002` and `firing threshold 1.0` via the
`snntorch.import_nir` mapping in
[notebook.py](../../neurocnl/backend/app/routers/notebook.py) (`dt=1e-4`,
`beta = 1 - dt/tau`, `threshold /= r*dt/tau`). The first LIF is the 784-neuron input encoder,
driven directly by pixel values in `[0, 1]`. Its membrane asymptote under a constant drive `x` is
`x / (1 - beta)` = `20x`, and the threshold is exactly 20 — so a pixel of 1.0 approaches the
threshold without ever reaching it, and everything downstream is starved.

So the board is not the problem, and neither is the deploy path any more. The next question is
whether that `w_scale`-corrected threshold is the right mapping for an input-encoding LIF, and it
should be answered against the training path, not the hardware one.

## Also fixed

- **"Overlay: Not installed" beside a loaded overlay.** Nothing ever wrote `overlayVersion` on the
  board record; `_apply_preflight_to_board`
  ([pynq_service.py](../../nmtk/launcher_control/pynq_service.py)) now takes it from the
  preflight's `overlay_assets.overlay_version`, and leaves the stored value alone when the board
  reports none.
- **The endless "Checking pynq z2."** The board's preflight costs **21 s** (measured) because it
  spawns an interpreter that imports `pynq` on the Zynq. The Deploy step fired it twice per visit,
  and re-ran `validate()`, which cleared the deploy ack — so walking to Review and back discarded a
  deploy the board was still holding. Now: a passing device probe is memoised for 30 s on the board
  ([routers/pynq.py](../../Neurochip/neurochip/app/routers/pynq.py)), the automatic pass no longer
  calls `checkReadiness` at all (the readiness provider has already preflighted), its key lives in
  the provider so it survives a remount, and an unchanged payload keeps the ack.

## Tests

- `tests/launcher_control/` — **305 pass** (was 303).
- `Neurochip/neurochip/tests/test_pynq_backend.py` + `test_pynq_sitl_verify.py` — **86 pass**
  (`-p no:nengo`), including a new `TestPynqHardwareProbeCache`.
- `neurocnl/backend/tests/test_notebook_dataset_sample.py` — 5 new.
- `neurocnl/neurocnl/handoff/test_neurochip_pynq_handoff.py` — 43 pass, including
  `test_a_threshold_is_never_scaled_twice`.
- `nmtk_ui_core` — **202 pass** (was 198).
- `neurocnl/frontend` — 1826 pass, 1 skipped, **2 failing before this work** and unrelated to it
  (`studio_responsive_audit_test.dart`, the Lava and Akida compact actions; both areas have
  uncommitted changes that predate this session).
