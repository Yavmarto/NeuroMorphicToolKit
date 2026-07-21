# Demo: LIF Keyword-Spotting SNN — reproducing the NeuroBench KWS baseline

Interview/portfolio demo across the 3 NeuroStudio canvasses. Research/algorithms framing:
reproduce a published neuromorphic benchmark, show the sparsity/energy advantage, deploy to real
silicon. See design rationale in `~/.claude/plans/looking-at-my-project-optimized-beaver.md`.

**Network:** MFCC(20) → LIF → Linear(256,20) → LIF → Linear(256,256) → LIF → Linear(35,256) → LIF → out(35). LIF-only (the one model exact on every backend; avoids the CubaLIF `node.tau` crash).

**Spec:** `neurocnl/examples/keyword_spotting.cnl` — validated: `compile_to_nir` → 9 nodes / 8 edges, all LIF. Round-trip valid against `NIR_Renderer`.

## Run order

All steps below are clicks inside the running NeuroStudio app (`make dev`, or
`cd nmtk/neuro_toolkit && flutter run -d macos`) once the backends are up
(`docker compose up -d`; `curl -s localhost:8000/health` → `{"status":"ok"}`
is just the pre-flight check, not something the demo itself does).

1. **Model canvas.** Load `keyword_spotting.cnl` into the CNL panel → Sync to Canvas. Toggle CNL ↔ NIR ↔ canvas to show all three mirror the same graph (the headline feature). Validation must pass.

2. **Train canvas — one-time offline prep (can't be avoided in-app):** neither
   "SpeechCommands" nor "MFCC" is a real option anywhere in the Train canvas —
   the dataLoader node's **Format** dropdown only offers
   `auto, tonic_nmnist, tonic_shd, npy, pt, hdf5`, and there's no registered
   `speech_commands` dataset (the catalog only has
   `mnist_spike, nmnist, dvs_gesture, shd, ntidigits`). Google Speech Commands
   isn't auto-downloadable and MFCC extraction isn't built in — you must
   precompute it yourself once, outside the app: download Speech Commands,
   extract 20-bin MFCC features per clip, save as a single `.pt` tensor
   (features + labels) on the machine running the backend. This is a real
   manual step, not a UI gap you can click around — say so on camera rather
   than pretending otherwise.

   **Script (run once, locally):**
   ```bash
   pip install torch torchaudio   # skip if already installed
   python3 scripts/prep_speech_commands_mfcc.py
   # → downloads ~2.3 GB to data/speech_commands_raw/
   # → writes  data/speech_commands_mfcc20.pt  (~90 MB, all three splits)
   #   tensor: TensorDataset( float32(N,20), int64(N,) )  35 classes
   ```
   Smoke-test first with `--dry-run` (200 clips/split, takes ~10 s).

   **Smoke-test:**
   ```bash
   python3 scripts/prep_speech_commands_mfcc.py --dry-run --out /tmp/kws_smoke.pt
   ```

   **Copy into the Docker backend (local compose):**
   ```bash
   # Find the suite_api container name
   docker ps --filter name=suite_api --format '{{.Names}}'
   # Copy the file in
   docker cp data/speech_commands_mfcc20.pt <container>:/home/app/data/speech_commands_mfcc20.pt
   ```

   **Copy to the remote host (moosebuntu) and into its container:**
   ```bash
   rsync -avz data/speech_commands_mfcc20.pt moosebuntu@192.168.2.51:~/NeuroMorphicToolKit/data/
   ssh moosebuntu@192.168.2.51 \
     "docker cp ~/NeuroMorphicToolKit/data/speech_commands_mfcc20.pt \
       \$(docker ps --filter name=suite_api -q):/home/app/data/speech_commands_mfcc20.pt"
   ```

   The path to enter in the UI:  `/home/app/data/speech_commands_mfcc20.pt`

3. **Train canvas — build the DAG.**

   Place these 9 nodes (the 8 from before, **plus `validationLoop`** — see
   why below), then wire these exact **port name → port name** connections
   (port names/types are fixed per node type, from `pipeline_dag.dart`'s
   `inputPorts`/`outputPorts`; each row is one wire from the source node's
   named output dot to the target node's named input dot):

   | # | From node . output port | To node . input port |
   |---|---|---|
   | 1 | dataLoader . `data` | spikeEncoder . `data` |
   | 2 | spikeEncoder . `spikes` | timeLoop . `spikes` |
   | 3 | timeLoop . `spikes` | forwardPass . `input` |
   | 4 | forwardPass . `spikes` | crossEntropyLoss . `spikes` |
   | 5 | dataLoader . `labels` | crossEntropyLoss . `labels` |
   | 6 | forwardPass . `spikes` | spikeRecorder . `input` |
   | 7 | crossEntropyLoss . `loss` | surrogateBackward . `loss` |
   | 8 | surrogateBackward . `gradients` | adamOptimiser . `gradients` |
   | 9 | adamOptimiser . `model` | validationLoop . `model` |
   | 10 | dataLoader . `data` | validationLoop . `val_data` |

   Notes on the non-obvious ones:
   - **Row 1 and row 5 are both wires out of dataLoader** — it has two output
     dots (`data` and `labels`); don't assume one wire covers both. Row 10 is
     a *third* wire out of dataLoader's `data` dot (fanning out to both
     spikeEncoder and validationLoop) — same "one dot, multiple wires"
     pattern as forwardPass below.
   - **Row 4 and row 6 are both wires out of forwardPass's single `spikes`
     output dot** — one output port fans out to two different target nodes
     (crossEntropyLoss and spikeRecorder). This is the one place a node has
     more outgoing wires than output dots — that's expected, a single dot can
     feed multiple input dots.
   - **Why `validationLoop` is required, not optional:** without it, nothing
     in the generated notebook ever writes trained weights to disk — the
     `torch.save(net.state_dict(), 'best_model.pt')` checkpoint is only
     emitted when a `validationLoop` node is present and wired to a model
     input. Skip this node and the Eval canvas will silently evaluate a
     **fresh, randomly-initialized** network instead of your trained one —
     this is exactly what produced a near-chance (~1.5%) eval accuracy after
     an otherwise-normal 50-epoch training run. `export_nir=true` does *not*
     substitute for this — it does not currently regenerate weights from the
     trained model.
   - Leave `validationLoop`'s own parameters at their defaults
     (`every_n_epochs=1`, `save_best_checkpoint=on`, `checkpoint_metric =
     val_accuracy`, `checkpoint_mode = max`) — no need to change anything in
     its property panel.
   - forwardPass also has an optional `model` **input** dot — leave it
     unconnected; it's only used if you add a State Reset/scheduler node,
     which this DAG doesn't need.

   Now set these exact node parameters (as they appear in each node's
   property panel):
   - **dataLoader** — Format = `pt`; Dataset Path = `/home/app/data/speech_commands_mfcc20.pt`; Batch Size = `32`; Shuffle = on.
   - **spikeEncoder** — Encoding = `rate` (the closest real option to a rate-coded MFCC front end — document this substitution, don't claim "MFCC encoding" is a dropdown choice); Time Window = `25`.
   - **timeLoop** — Time Steps = `25`.
   - **forwardPass** — no configurable fields (read-only "Eval Mode" indicator).
   - **crossEntropyLoss** — Label Smoothing = `0.0`.
   - **surrogateBackward** — Function = `fast_sigmoid`; Slope = `25.0`. (Use this node, not a separate "BPTT" node — there isn't one with a configurable panel.)
   - **adamOptimiser** — Learning Rate = `0.001`; Weight Decay = `0.0`; Beta 1 = `0.9`; Beta 2 = `0.999`.
   - **spikeRecorder** — no configurable fields.
   - Gear icon (Pipeline Settings) — Epochs = `50` (raise if accuracy plateaus below the 0.75 target); Random Seed = `42`.
   - `export_nir=true` is set automatically when you use the Run step below — not a separate field to hunt for.

4. **Run step → click Start.** This generates and executes the training notebook server-side (snnTorch) with live epoch/loss progress — no manual notebook execution needed. Target ≥ 0.75 top-1 (the benchmark `pass_threshold`); the trained NIR is picked up automatically by the next step.
5. **Eval canvas.** There is no separate "network" node type — place
   **dataLoader** (or **testLoader**), **forwardPass**, and **accuracyMetric**
   (dataLoader/forwardPass are the same node types as the Train canvas), then
   wire:

   | # | From node . output port | To node . input port |
   |---|---|---|
   | 1 | dataLoader . `data` | forwardPass . `input` |
   | 2 | forwardPass . `spikes` | accuracyMetric . `spikes` |
   | 3 | dataLoader . `labels` | accuracyMetric . `labels` |

   Row 3 is a wire straight from dataLoader to accuracyMetric, bypassing
   forwardPass — same "one node, two output wires" pattern as the Train
   canvas's dataLoader. **Correction — forwardPass's `model` input is *not*
   auto-populated:** there is no mechanism that carries trained weights from
   the Train canvas into a separately-generated Eval notebook. Without the
   `validationLoop` checkpoint node added to the Train DAG in step 3 (which
   writes `best_model.pt` next to the notebook), Eval silently evaluates a
   fresh random-init network and gives a near-chance result — this is not
   automatic, it depends on step 3's `validationLoop` node having run first.
   **accuracyMetric is the only one of the four `keyword_spotting.json`
   metrics available as an Eval-canvas node** — `activation_sparsity`,
   `synaptic_operations`, and `memory_kb` are not canvas nodes at all; they're
   computed by the NeuroBench benchmark run in step 6 below, so don't go
   looking for extra metric nodes to wire in for them.
6. **Results step → Run Benchmark.** ⚠️ **Currently unreliable/likely broken** — the
   `NeurobenchPanel` widget that owns this button isn't wired into the Results
   step anywhere in the frontend, and its backend call omits a required
   `network_path`, which should hard-error rather than return a real score.
   If you see epoch/accuracy numbers displayed here, verify they're not
   actually the Train canvas's own training telemetry bleeding through — treat
   this step as needing its own investigation before trusting any number it
   shows, and don't present it live until that's resolved. When it does work,
   it's meant to run the builtin NeuroBench `keyword_spotting` benchmark and
   show the results table in-app to fill `results_vs_baseline.md` from.
7. **Results step → Deploy to Hardware.** Select a target and click through its readiness/deploy buttons in order — in-app, real click-paths for:
   - **Akida** (`akida_workspace.dart`) — Check Readiness → Map Runtime → Generate Package/Install/Run. See `AKIDA_DEPLOYMENT.md` for the full walkthrough and caveats.
   - **Lava / Loihi2** (`lava_workspace.dart`) — Check Readiness → Run, against the Neurochip Loihi2 simulator contract.

   Record on-hardware (Akida) and simulator (Lava/Loihi2) accuracy + energy;
   label estimated vs measured (Neurochip's power/latency estimation is
   surfaced in the same workspace).

   SpiNNaker2 and Sinabs are export/preview-only in the app today (no in-app
   deploy-to-hardware call exists for either) — don't present them as
   one-click; if you need those boards, that's a separate follow-up, not part
   of this demo's live flow.

## Result tables to fill

`results_vs_baseline.md` — our model vs seeded NeuroBench v1.0 baselines (CPU/PyTorch, Loihi2/Lava, SpiNNaker2, Xylo). The demo covers a subset of the "Ours" rows in-app (snnTorch sim, Akida on-hardware/simulator, Lava/Loihi2 simulator) — SpiNNaker2/Xylo/CPU rows can only be filled with the published NeuroBench baseline numbers, not our own reproduction:

| Backend | Top-1 acc | Activation sparsity | Synaptic ops | Memory (KB) |
|---|---|---|---|---|
| Ours (snnTorch sim) | | | | |
| Ours (Akida, on-hardware) | | | | |
| Ours (Lava/Loihi2, simulator) | | | | |
| NeuroBench published (CPU/PyTorch, Loihi2/Lava, SpiNNaker2, Xylo) | | | | |

## Honest caveats (say these — they read as competence)
- LIF-only by design (CubaLIF crashes on brian2/pynn/akida per `nir_support.py`).
- brian2/pynn/akida LIF is graded `approximate` (some params hardcoded) → quote snnTorch/Lava as primary.
- Training executes server-side when you click Start (a real notebook run, not a mock) — the in-process Nengo preview elsewhere in the app is a separate, faster, non-training path; don't conflate the two on camera.
- MFCC preprocessing only (Speech2Spikes is proprietary and blocked in `neurobench_executor.py`).
- Akida's on-chip activation is a quantized, fused-into-layer nonlinearity, not literal spiking integrate-and-fire — see `AKIDA_DEPLOYMENT.md` for the full caveat.
