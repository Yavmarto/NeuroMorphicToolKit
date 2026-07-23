# Studio end-to-end demo walkthrough

A literal click-through checklist for demoing the full nmtk pipeline — author →
validate → train → eval → deploy — using the real running backend and the real
Flutter Studio app, against **moosebuntu@192.168.2.51** (the dev box with the
physical Akida AKD1000 and PYNQ-Z2 attached). No standalone scripts. Each step
names what to click and what tells you it worked.

Honesty ceiling for this demo, stated up front:
- **Akida**: the backend and Neurochip worker now run on moosebuntu (Linux,
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
make docker-ex-m REMOTE_HOST=moosebuntu@192.168.2.51 AKIDA_NATIVE=1
```
This rsyncs any uncommitted changes, rebuilds `suite_api` on moosebuntu,
starts the native `neurochip.service` there (so the physical AKD1000 is in
the loop, not a container-only stub), and launches the local macOS Flutter
Studio app already pointed at that host — no separate terminal or manual
`--dart-define` needed.

Confirm:
```bash
curl http://192.168.2.51:9000/api/suite/health
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

1. Framework: pick **`snntorch_sim`** as the simulator/training backend.
2. Dataset: open the dataset picker and select **SHD** ("Spiking Heidelberg
   Digits"). Clicking "Download dataset" here uses a separate,
   Firebase-backed fetch path — note that it isn't actually required for
   this demo to work; the real data comes from `tonic`'s own auto-download,
   set up in the next step. Don't assume the Setup click alone makes
   training functional.

## 4. Model / Training DAG / Eval DAG steps

- **Model step**: confirm `shd_digit_classifier.cnl`'s network is reflected
  (3 populations, as in step 2.5). Click through each node and confirm these
  literal property-panel values (verified directly against the backend's
  `canonical_from_cnl()` output for this exact template, not guessed from the
  CNL source alone — field labels come from
  `frontend/lib/providers/canvas/nir_types_provider.dart`):
  - `input` (nir.Input): **Size** 700.
  - `cochlea` (nir.LIF): **Neurons** 700, **Tau** 0.02s, **Threshold** 0.8,
    **Resistance** 1.0, **Leak** 0.0.
  - `w_cochlea_hidden` (nir.Linear): **Rows** 128 (→ hidden), **Cols** 700
    (→ cochlea) — the `(→ name)`/`(← name)` annotation is this session's fix
    (`frontend/lib/widgets/canvas/property_panel.dart`); confirm it actually
    renders next to the label, not just the bare number.
  - `hidden` (nir.LIF): **Neurons** 128, **Tau** 0.02s, **Threshold** 0.6,
    **Resistance** 1.0, **Leak** 0.0.
  - `w_hidden_classes` (nir.Linear): **Rows** 20 (→ classes), **Cols** 128
    (→ hidden).
  - `classes` (nir.LIF): **Neurons** 20, **Tau** 0.03s, **Threshold** 0.7,
    **Resistance** 1.0, **Leak** 0.0.
  - `output` (nir.Output): **Size** 20.

  Two fields will look "wrong" and aren't part of this session's fix — call
  them out during a demo rather than let them look like new bugs:
  - **Time Step** on every LIF node will show the form default **0.0001s**,
    not the network's real declared timestep (**0.001s**, from `Define a
    network ... with timestep 0.001`). The backend puts the network's `dt`
    on the node's `metadata` map, but the property panel only ever reads
    `node.parameters`, which has no `dt` key for LIF nodes — so the two never
    meet. Pre-existing gap, not touched this session.
  - **Fill** on both Linear nodes will show a real-looking decimal (e.g.
    `0.0466...`, `0.0613...`), not the `1.0` default — but that's the raw
    weight matrix's `[0][0]` entry (`weight.flat[0]` in
    `backend/app/services/nir_graph_serializer.py`), not an actual fill
    value. Both templates' weights are Xavier-initialized full matrices
    (`weight_init: "xavier"` metadata), not a uniform fill — so this field
    never meant anything for them and shouldn't be read as one.
- **Training DAG**: the app auto-builds this the first time you open the tab
  (`buildDefaultPhases()`, keyed on the `snntorch_sim` framework choice —
  same fixed chain regardless of which network is loaded). Confirm the real
  chain renders:
  `dataLoader → stateReset → timeLoop → forwardPass → mseCountLoss →
  surrogateBackward → adamOptimiser → lossLogger`, plus a parallel
  validation branch off the optimiser: `testLoader → validationLoop`.
  Click through each node and confirm/set these literal parameter values
  (all in the node's property panel — this is the CNL-free node-graph
  editing referenced above):
  - `dataLoader`: a blue "SHD · from setup" chip should already show at the
    top of the panel. **Change Format from `auto` to `tonic_shd`** in the
    dropdown (`auto`/`tonic_nmnist`/`tonic_shd`/`npy`/`pt`/`hdf5`) — this is
    the one value that actually matters; leaving it on `auto` silently
    generates a non-functional placeholder loader instead of real code.
    Also confirm `batch_size: 32`, `shuffle: true`, `time_window_ms: 1`.
  - `stateReset`, `forwardPass`, `lossLogger`: no parameters.
  - `timeLoop`: `num_steps: 25`.
  - `mseCountLoss`: `correct_rate: 0.8`, `incorrect_rate: 0.2`.
  - `surrogateBackward`: `function: fast_sigmoid`, `slope: 25.0`.
  - `adamOptimiser`: `lr: 0.001`, `weight_decay: 0.0`, `beta1: 0.9`,
    `beta2: 0.999`.
  - `testLoader` (validation branch): same "SHD · from setup" chip — set
    **Format to `tonic_shd`** here too, `batch_size: 32`, `shuffle: false`.
  - `validationLoop`: `every_n_epochs: 1`, `save_best_checkpoint: true`,
    `checkpoint_metric: val_accuracy`, `checkpoint_mode: max`.
- **Eval DAG**: same auto-build-once behavior. Confirm the real chain:
  `testLoader → stateReset → forwardPass → accuracyMetric`.
  - `testLoader`: **Format `tonic_shd`**, `batch_size: 32`, `shuffle: false`.
  - `stateReset`, `forwardPass`: no parameters.
  - `accuracyMetric`: `top_k: 1`.

(The chain/names above correct an earlier version of this doc, which said
`dataLoader → forwardPass → ceCountLoss → surrogateBackward → adamOptimiser`
for Training and `dataLoader → forwardPass → accuracyMetric` for Eval — wrong
loss-node name and missing `stateReset`/`timeLoop`/`lossLogger`/
`validationLoop`/`testLoader` throughout.)

## 5. Notebook step

Generate cells, run them. On first Run, `tonic` downloads SHD itself over the
network (on moosebuntu, since that's where the backend runs per step 1) —
this can take a few minutes the first time. Confirm no "implausible firing
threshold" warning cell appears (that warning fires when a network is
authored without a sensible declared timestep — it shouldn't for
`shd_digit_classifier.cnl`).

## 6. Run step

Watch live per-epoch metrics stream in as training runs.

## 7. Deploy step — Akida (already fully wired)

Switch back to the `reflex_arc` network loaded in step 2 for this section and
the next — `shd_digit_classifier`'s 3 real populations exceed PYNQ's fixed
2-population overlay limit (see the CNL-scope callout above), so it isn't
used for Deploy.

1. Select the **Akida** hardware target.
2. Run the exportability check — confirm a support-state verdict, topology
   verdict, and (if exportable) a mapped-network summary.
3. Attempt the Neurochip handoff button — confirm it either opens/deep-links
   into Neurochip and attempts a real handoff to the AKD1000 on moosebuntu, or
   reports a clear reason it can't (e.g. no paired host).
4. Note explicitly: whether this results in an actual flashed chip now
   depends on Neurochip's host-pairing state on moosebuntu — confirm live,
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
   instead: `curl -X POST http://192.168.2.51:9000/api/deploy/pynq/network
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
- This demo now runs against moosebuntu (192.168.2.51) instead of localhost —
  the standalone `neurocnl` compose path (port 8000) is a separate, smaller
  setup; the integrated stack used here runs on port **9000**.
- `shd_digit_classifier.cnl` (new template — `neurocnl/backend/app/templates/`)
  and its gallery entry (`neurocnl/backend/app/routers/templates.py`,
  `_TEMPLATE_META`) are new this session, added specifically so this guide
  could name a real, working dataset instead of "pick or import a dataset."

## Restart info

Re-run the same command:
```bash
make docker-ex-m REMOTE_HOST=moosebuntu@192.168.2.51 AKIDA_NATIVE=1
```
It's idempotent (rsync + rebuild + relaunch). For Dart-only changes, hot-reload
(`r`) in the running `flutter run` session instead of restarting the whole
command.
