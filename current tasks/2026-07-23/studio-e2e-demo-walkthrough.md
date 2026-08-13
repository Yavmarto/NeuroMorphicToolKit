# Studio end-to-end demo walkthrough

A literal click-through checklist for demoing the full nmtk pipeline — author →
validate → train → eval → deploy — using the real running backend and the real
Flutter Studio app, against **moosebun2@192.168.2.90** (the dev box with the
physical Akida AKD1000 and PYNQ-Z2 attached). No standalone scripts. Each step
names what to click and what tells you it worked.

Honesty ceiling for this demo, stated up front:
- **Akida**: the backend and Neurochip worker now run on moosebun2 (Linux,
  board physically attached, native `neurochip.service` when started with
  `AKIDA_NATIVE=1`), so the Neurochip handoff step can now attempt a **real**
  flash, not just a preflight — the `akida` Python package still doesn't
  support macOS, but that no longer matters since the backend isn't running on
  the Mac anymore. Confirm live at demo time — host-pairing behavior wasn't
  re-verified this session, so don't promise a guaranteed flash in advance.
- **PYNQ-Z2**: the exportability check now also returns a populated
  `deploy_payload` (weights, register map, overlay id) targeting the
  **pre-loaded overlay-v1 bitstream** already on the board. It still does
  **not** generate a new overlay/bitstream — the FINN compile stage remains an
  unbuilt Phase-2 placeholder (`neurocnl/docs/support_matrix.md`). Don't
  present this as "full FPGA deploy."

CNL scope, stated up front (this trips people up): **CNL only describes
network architecture** (populations, connections, neuron params) — it has no
concept of a training/eval pipeline at all. The grammar
(`neurocnl/neurocnl/nir_cnl/grammar_tables.py`) supports exactly three flat,
scalar sentences (`Train the network for N epochs...`, `Evaluate the
network...`, `Export the trained network to...`) with plain fields like
epochs/learning_rate/batch_size — no node graph, no `dataLoader`/
`forwardPass`/etc. Those node names exist only in the Flutter app
(`frontend/lib/models/canvas/pipeline_dag.dart`). The **Training DAG** and
**Eval DAG** canvases are separate, auto-built-once node graphs — the app
generates a fixed default chain the first time you open each tab (keyed only
on the chosen simulator framework), and you edit it directly on that canvas
(click a node, edit its parameter fields) — there is no CNL editor or CNL
import for these, and there isn't supposed to be one. Importing a `.cnl` file
only ever touches the Model/Architecture canvas.

Two different networks are used in this walkthrough, for two different
reasons: **`shd_digit_classifier.cnl`** (new this session — a real 3-layer
classifier) drives the Setup → Model → Training DAG → Eval DAG → Notebook →
Run steps, so the guide can name one real, working dataset. **`reflex_arc.cnl`**
is still used for the Deploy steps (7-8) — PYNQ's fixed overlay-v1 hardware
contract only supports 2 real neuron populations, and the classifier has 3, so
it can't be the network used there. Load whichever one the current step needs.

## 1. Start the backend + Studio app

From the repo root:
```bash
make docker-ex-m REMOTE_HOST=moosebun2@192.168.2.90 AKIDA_NATIVE=1
```
This rsyncs any uncommitted changes, rebuilds `suite_api` on moosebun2,
starts the native `neurochip.service` there (so the physical AKD1000 is in
the loop, not a container-only stub), and launches the local macOS Flutter
Studio app already pointed at that host — no separate terminal or manual
`--dart-define` needed.

Confirm:
```bash
curl http://192.168.2.90:9000/api/suite/health
```
expecting `{"suiteApiStatus": "ready"}`. Confirm the Studio window opens to
the canvas/pipeline screen.

## 2. Canvas: load a network, confirm the timestep field

1. Open the template gallery, load `reflex_arc.cnl` (used later, for Deploy).
2. Click empty canvas space (deselect any node) — the property panel switches
   to the **Network Settings** panel.
3. Confirm the "Network Timestep (s)" field shows a populated value (this
   template was recalibrated with a `with timestep` clause this session).
4. Edit the value, then click a node and back to empty canvas — confirm the
   edited value is still there. This proves the timestep survives a live
   canvas-edit round trip, not just a fresh template load.
5. Now load `shd_digit_classifier.cnl` instead (new this session — category
   "Signal Processing" in the gallery) — this is a separate load, not a
   merge, and is the network the rest of Setup → Run below actually uses.
   Confirm the canvas shows 3 LIF populations (`cochlea`, `hidden`,
   `classes`) chained input(700) → cochlea → hidden(128) → classes(20) →
   output(20).

## 3. Setup step

1. Framework: pick **`snntorch_sim`**. This target has two distinct surfaces:
   the fixed-weight runtime simulator and the generated snnTorch notebook
   training path; this walkthrough exercises the latter.
2. Dataset: select **SHD** ("Spiking Heidelberg Digits"). The Setup download
   status is useful evidence that the catalog path works, but it is not the
   notebook's data source: the generated notebook uses `tonic.datasets.SHD`
   and downloads its own train/test archives into the notebook's `data/`
   directory.
3. Ensure the notebook environment has `tonic`, `torch`, and `snntorch`.
   If the generated notebook reports `pip install tonic`, install it in the
   notebook kernel environment and regenerate; do not treat a successful
   Setup download alone as successful training.

## 4. Model / Training DAG / Eval DAG steps

- **Model step**: load `shd_digit_classifier.cnl` from the gallery entry
  defined by `backend/app/templates/shd_digit_classifier.cnl` and
  `backend/app/routers/templates.py`. Confirm the available graph is
  `input(700) → cochlea(700) → hidden(128) → classes(20) → output(20)`;
  do not widen it to `700 → 256 → 256 → 20` for the first smoke run.
- **Training DAG**: keep the available data, state, time, forward, backward,
  optimiser, logging, and validation nodes. Set the nodes as follows:
  - `dataLoader`: **Format `tonic_shd`**, `batch_size: 32`,
    `shuffle: true`, `time_window_ms: 4`.
  - `stateReset`, `forwardPass`, `lossLogger`: no parameters.
  - `timeLoop`: leave the available `num_steps: 25` default; tonic framing
    controls the actual padded sequence length when `time_window_ms` is set.
  - Replace the default `mseCountLoss` with the available **`ceCountLoss`**
    node. There is no `ceRateLoss` node in the current frontend/backend
    contract, so do not add that name manually to the canvas or guide.
  - `surrogateBackward`: `function: fast_sigmoid`, `slope: 25.0`.
  - `adamOptimiser`: `lr: 0.001`, `weight_decay: 0.0`, `beta1: 0.9`,
    `beta2: 0.999`.
  - Validation branch: wire a `testLoader` to `validationLoop.val_data`,
    set `Format: tonic_shd`, `batch_size: 32`, `shuffle: false`,
    `time_window_ms: 4`, and set `every_n_epochs: 1`,
    `save_best_checkpoint: true`, `checkpoint_metric: val_accuracy`,
    `checkpoint_mode: max`.
- **Eval DAG**: use `testLoader → stateReset → forwardPass →
  accuracyMetric`. Set `testLoader` to `Format: tonic_shd`, `batch_size: 32`,
  `shuffle: false`, `time_window_ms: 4`, and keep `accuracyMetric` at `top_k: 1`.

The generated backend code is the source of truth for the tensor boundary:
Tonic frames use SHD microsecond timestamps, so `time_window_ms: 4` becomes
`ToFrame(..., time_window=4000)`. `PadTensors(batch_first=False)` and the
snntorch model together produce `[T, B, N]`; `ceCountLoss` consumes that
spike train with `[B]` integer targets, while validation/evaluation reduce
over time and use `argmax(-1)` over the class dimension.

## 5. Notebook step

Generate the notebook and inspect the generated cells before running:

1. Dataset cell: `tonic.datasets.SHD`, a `ToFrame` transform, and
   `PadTensors(batch_first=False)` must all be present.
2. Architecture cell: `class Net` must load the generated
   `weights_snntorch_sim_<hash>.npz` artifact.
3. Train cell: the loss call must be `loss_fn(spk_out, targets)` and the
   validation call must use `_vl_spk_out` with `_vl_targets`.
4. Run the notebook in order. Record these as separate checkpoints:
   dataset download, notebook generation, first batch, first loss/backward,
   validation event, and final evaluation accuracy. A download is not a
   training result.

The notebook's optional Python-export cell now requires a saved notebook in
its workspace directory and discovers the single `.ipynb` file there; it no
longer invokes `nbconvert` with notebook-undefined `__file__`. If there are
multiple notebooks in that directory, follow the cell's actionable error
instead of guessing which file to export.

## 6. Run step

Watch the streamed train and validation events. Treat shape warnings,
dimension errors, no validation event, repeated zero loss, or a zero-spike
network as a failed run to report and diagnose; do not call the run
"successful" because the SHD archive downloaded.

### Smaller custom KWS alternative

The repository also contains `neurocnl/examples/keyword_spotting.cnl` and
`scripts/data/speech_commands_mfcc20.pt`, but this is **not** the primary
Studio recipe: the CNL file is an example rather than a confirmed gallery
template, and the bundled `.pt` artifact does not establish a true held-out
test split. To experiment with it, run
`scripts/prep_speech_commands_mfcc.py`, apply
`scripts/normalize_mfcc_features.py`, mount the resulting `.pt` file through
the `dataLoader`'s existing `format: pt` and `dataset_path` fields, and label
any evaluation as custom-data smoke evidence unless separate train/test
artifacts are supplied.

## 7. Deploy step — Akida (already fully wired)

Switch back to the `reflex_arc` network loaded in step 2 for this section and
the next — `shd_digit_classifier`'s 3 real populations exceed PYNQ's fixed
2-population overlay limit (see the CNL-scope callout above), so it isn't
used for Deploy.

1. Select the **Akida** hardware target.
2. Run the exportability check — confirm a support-state verdict, topology
   verdict, and (if exportable) a mapped-network summary.
3. Attempt the Neurochip handoff button — confirm it either opens/deep-links
   into Neurochip and attempts a real handoff to the AKD1000 on moosebun2, or
   reports a clear reason it can't (e.g. no paired host).
4. Note explicitly: whether this results in an actual flashed chip now
   depends on Neurochip's host-pairing state on moosebun2 — confirm live,
   don't assume it from this doc alone.

## 8. Deploy step — PYNQ-Z2 (new this session)

1. Select the **PYNQ-Z2** hardware target (now present in the target list).
2. Confirm the panel runs a check automatically, and shows a support-state
   card (exportable / exportable-with-warnings / not-exportable) plus a
   network summary (neurons, synapses, estimated memory).
3. Try a bit-width choice chip (8/16/32-bit) and confirm re-running the check
   updates the verdict.
4. To exercise the rejection path: load or author a network that exceeds the
   PYNQ overlay's synapse limit, or force an unsupported bit-width, and
   confirm rejections render in red.
5. The panel itself only renders the support-state card (verdict, warnings,
   rejections, network summary) — it does not yet display the deploy payload.
   To see the effect of this session's backend fix, call the API directly
   instead: `curl -X POST http://192.168.2.90:9000/api/deploy/pynq/network
   -H 'Content-Type: application/json' -d '{"spec": "<reflex_arc.cnl text>",
   "weight_bit_width": 8}'` and confirm `deploy_payload` is populated
   (weights, register map, overlay id) instead of `null`.
6. Note explicitly: this still targets the fixed, pre-loaded overlay-v1
   bitstream — no new overlay/bitstream file is generated (Phase-2 FINN stage
   is still a placeholder). The panel's own "verdict-only" disclaimer text is
   still accurate and hasn't been changed — only the API response payload
   changed, not what the Studio UI surfaces from it.

## Where to notice the difference

- The PYNQ-Z2 target is new in the Deploy step's target list (previously only
  Akida, Lava, and SC-NeuroCore FPGA were selectable hardware targets) — new
  files: `lib/providers/pynq_deploy_provider.dart`, `lib/widgets/pynq_deploy_panel.dart`.
  It calls the pre-existing backend endpoint `POST /api/deploy/pynq/network`,
  which was previously unreachable from the live app.
- That endpoint's `deploy_payload` field, previously hardcoded to `null`
  (`neurocnl/backend/app/routers/deploy.py`, comment: "Nengo-backed artifact
  generation removed"), is now built directly from the lowered IR via a new
  Nengo-free path — `export_pynq_artifact_from_ir()` in
  `neurocnl/neurocnl/export/pynq_exporter.py` — reusing the existing,
  previously-orphaned `build_pynq_deploy_payload()` handoff builder.
- This demo now runs against moosebun2 (192.168.2.90) instead of localhost —
  the standalone `neurocnl` compose path (port 8000) is a separate, smaller
  setup; the integrated stack used here runs on port **9000**.
- `shd_digit_classifier.cnl` (new template — `neurocnl/backend/app/templates/`)
  and its gallery entry (`neurocnl/backend/app/routers/templates.py`,
  `_TEMPLATE_META`) are new this session, added specifically so this guide
  could name a real, working dataset instead of "pick or import a dataset."

## Restart info

Re-run the same command:
```bash
make docker-ex-m REMOTE_HOST=moosebun2@192.168.2.90 AKIDA_NATIVE=1
```
It's idempotent (rsync + rebuild + relaunch). For Dart-only changes, hot-reload
(`r`) in the running `flutter run` session instead of restarting the whole
command.
