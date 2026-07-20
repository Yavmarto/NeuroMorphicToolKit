# Demo: LIF Keyword-Spotting SNN — reproducing the NeuroBench KWS baseline

Interview/portfolio demo across the 3 NeuroStudio canvasses. Research/algorithms framing:
reproduce a published neuromorphic benchmark, show the sparsity/energy advantage, deploy to real
silicon. See design rationale in `~/.claude/plans/looking-at-my-project-optimized-beaver.md`.

**Network:** MFCC(20) → LIF → Linear(256,20) → LIF → Linear(256,256) → LIF → Linear(35,256) → LIF → out(35). LIF-only (the one model exact on every backend; avoids the CubaLIF `node.tau` crash).

**Spec:** `neurocnl/examples/keyword_spotting.cnl` — validated: `compile_to_nir` → 9 nodes / 8 edges, all LIF. Round-trip valid against `NIR_Renderer`.

## Run order

1. **Backends + launcher.** `docker compose up -d`; `curl -s localhost:8000/health` → `{"status":"ok"}`; then `make dev` (or `cd nmtk/neuro_toolkit && flutter run -d macos`).
2. **Model canvas.** Load `keyword_spotting.cnl` into the CNL panel → Sync to Canvas. Toggle CNL ↔ NIR ↔ canvas to show all three mirror the same graph (the headline feature). Validation must pass.
3. **Train canvas.** Build the DAG: dataLoader(SpeechCommands) → spikeEncoder(rate/MFCC) → timeLoop → forwardPass → CrossEntropy → backward(surrogate/BPTT) → Adam → spikeRecorder. `training_config.json`: set `export_nir=true`. Train in the Jupyter worker (snnTorch). Target ≥ 0.75 top-1 (the benchmark `pass_threshold`). Save the emitted NIR as `trained.nir`.
4. **Eval canvas.** DAG: data → network(trained.nir) → metrics = accuracy, activation_sparsity, synaptic_operations, memory_kb (exactly the `keyword_spotting.json` metrics).
5. **Neurobench.** `POST /run` the builtin `keyword_spotting` benchmark; fill `results_vs_baseline.md`.
6. **Ablation sweep.** `POST /sweep` over firing threshold (or timesteps); save accuracy-vs-energy plot.
7. **Hardware.** Export `trained.nir` via `neurocnl/neurocnl/export/{loihi,spinnaker2,sinabs}_exporter.py` for your board → deploy through the matching `Neurochip/.../routers/*` route → record on-hardware accuracy + energy (label estimated vs measured; Neurochip `estimation.py` for estimates).

## Result tables to fill

`results_vs_baseline.md` — our model vs seeded NeuroBench v1.0 baselines (CPU/PyTorch, Loihi2/Lava, SpiNNaker2, Xylo):

| Backend | Top-1 acc | Activation sparsity | Synaptic ops | Memory (KB) |
|---|---|---|---|---|
| Ours (snnTorch sim) | | | | |
| Ours (on-hardware) | | | | |
| NeuroBench published | | | | |

## Honest caveats (say these — they read as competence)
- LIF-only by design (CubaLIF crashes on brian2/pynn/akida per `nir_support.py`).
- brian2/pynn/akida LIF is graded `approximate` (some params hardcoded) → quote snnTorch/Lava as primary.
- Training runs in the Jupyter worker, separate from the in-process Nengo preview.
- MFCC preprocessing only (Speech2Spikes is proprietary and blocked in `neurobench_executor.py`).
