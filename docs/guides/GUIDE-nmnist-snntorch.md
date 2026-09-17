# Guide: N-MNIST spiking CNN on snnTorch (simulation)

**Paper:** Orchard et al. 2015 — "Converting Static Image Datasets to Spiking Neuromorphic Datasets Using Saccades"  
**Reference baseline:** ~98–99% test accuracy for comparable spiking CNNs; eval-only notebook in `paper/02_cnn/gen_snn.ipynb` reports **97.97%** with pretrained NIR weights.  
**NMTK path:** `snntorch_sim` — load N-MNIST, train, export NIR, evaluate on the simulator.

This guide is **simulation only**. No Akida card or other neuromorphic hardware is required.

---

## What you will do

1. Load the committed N-MNIST CNN workspace (`2×34×34` event frames → three conv blocks → 10 classes).
2. Generate and run the snnTorch training notebook on your backend.
3. Export trained weights to NIR and read test accuracy from the eval phase.

Topology matches `paper/02_cnn/gen_snn.ipynb`.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Running NMTK backend | Suite API healthy at `http://<host>:9000/api/suite/health` |
| Jupyter worker | `jupyter-server` container running (notebook execution) |
| `neurocli` installed | `python3 -m pip install -e "./neurocli[dev]"` from the repo root |
| Auth (if enabled) | Set `NMTK_ADMIN_TOKEN` when `NMTK_AUTH_REQUIRED` is on |
| Dataset | First run downloads N-MNIST via `tonic` (~1.5 GB). Offline hosts must pre-seed `data/NMNIST/{Train,Test}` with ≥10 000 `.bin` files per split. |
| GPU (recommended) | CPU works but each epoch is slow on large batches |

---

## Path A — CLI (recommended for reproducibility)

Committed workspace: [`neurocli/neurocli/golden_paths/nmnist_cnn_snntorch.nmtk`](../../neurocli/neurocli/golden_paths/nmnist_cnn_snntorch.nmtk)

### 1. Smoke-generate only

Confirms CNL compiles and the backend returns `support: exact` without starting training:

```bash
cd neurocli
python3 -c "
from pathlib import Path
from neurocli.studio import generate_workspace
out = generate_workspace(
    Path('neurocli/golden_paths/nmnist_cnn_snntorch.nmtk'),
    epochs=1,
    registry='http://<your-host>:9000',
)
nb = out['notebooks'][0]
print(nb['target'], nb.get('support_level'), nb['filename'])
"
```

**Expected output (one line):**

```
snntorch_sim exact pipeline_snntorch_sim.ipynb
```

### 2. Full train + eval (20 epochs)

```bash
export NMTK_ADMIN_TOKEN='<token-if-required>'
neuro studio run neurocli/golden_paths/nmnist_cnn_snntorch.nmtk \
  --api-url http://<your-host>:9000 \
  --epochs 20 \
  --batch-size 64
```

Or use the headless runner (same API calls, writes a JSON summary):

```bash
NMTK_ADMIN_TOKEN='<token-if-required>' \
  python3 scripts/cel263_nmnist_e2e.py \
    --api-url http://<your-host>:9000 \
    --epochs 20
```

**Expected progress (human mode):**

```
Generating notebook...
Running cel263-nmnist-cnn/notebooks/pipeline_snntorch_sim.ipynb for 20 epochs...
  job_id=<uuid>
  epoch 1/20: loss=..., acc=...
  ...
  done.
{"status": "ok", "test_accuracy": <float>, "summary_path": "..."}
```

**Typical runtime:** ~30–90 minutes for 20 epochs on a mid-range GPU; first epoch is slowest while tonic caches frames. A 1-epoch smoke run is ~25–45 minutes on CPU-heavy dev rigs.

**Expected accuracy:** Val/test accuracy should climb well above chance (10%) within the first few epochs. Published Orchard-style CNNs reach **~98%**; from-scratch training in NMTK has not yet been benchmarked to that ceiling on every host — treat 90%+ as a healthy run, 98%+ as matching the paper.

---

## Path B — NeuroStudio (app)

1. Open **NeuroStudio** → **Setup** → **Dataset** → **NMNIST**.
2. **Target platform** → tick **snnTorch** only.
3. **Model** → load gallery template or paste the CNL from the golden-path workspace.
4. **Training** → `tonic_nmnist` loader, batch 64, `time_window_ms` 1, CE count loss, surrogate `fast_sigmoid` slope 25, Adam lr 0.001, validation loop with best checkpoint.
5. **Eval** → test loader with `load_best_checkpoint: on`, accuracy metric.
6. **Pipeline → Generate** → confirm `pipeline_snntorch_sim.ipynb`.
7. **Run** → watch epoch SSE in Results.

The generated notebook includes a **NIR Exporter** node when the pipeline requests NIR export; trained weights land under the workspace `artifacts/` folder.

---

## Expected artifacts

| Artifact | Location |
|---|---|
| Training notebook | `<workspace>/notebooks/pipeline_snntorch_sim.ipynb` |
| Best checkpoint | `<workspace>/artifacts/best_model.pt` |
| NIR export | `<workspace>/artifacts/trained.nir` (when exporter node present) |
| JSON summary (CLI runner) | `cel263_nmnist_summary.json` in scratch dir |

---

## Known failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `Temporary failure in name resolution` during dataset cell | Jupyter container cannot reach Mendeley/Zenodo | Pre-seed `NMNIST` bins under the workspace `data/` path, or add DNS to the jupyter service |
| `POST ... 401/403` | Auth required | Export `NMTK_ADMIN_TOKEN` (maps to `X-NMTK-Admin-Token`) |
| Job stalls with no epoch events for >30 min | Long first epoch on CPU or jupyter OOM | Use GPU worker, reduce to `--epochs 1` for smoke, or raise jupyter execution timeout |
| `tonic` "not enough files" | Fewer than 10 000 `.bin` per split | Download full N-MNIST archive; partial subsets are rejected |
| SSE disconnect mid-run | `jupyter-server` restarted | Re-poll: `python3 scripts/cel263_nmnist_e2e.py --poll-only <job_id> --epochs 20` |
| Accuracy stays near 10% | Wrong loader wiring or empty checkpoint | Regenerate notebook; confirm eval loader has `load_best_checkpoint: true` |

---

## Verification log

| Step | Status | Date |
|---|---|---|
| CNL compile (local) | ✅ 15-node CNN graph | 2026-09-15 |
| `generate-v2` → `support: exact` | ✅ on dev backend | 2026-09-15 |
| 20-epoch training to paper accuracy | ⏸ pending host reachability | 2026-09-17 |

See [`current tasks/2026-09-15/CEL-263-nmnist-e2e-findings.md`](../../current%20tasks/2026-09-15/CEL-263-nmnist-e2e-findings.md) for the full engineering log.
