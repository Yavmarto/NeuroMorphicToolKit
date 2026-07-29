# MNIST FCN baseline for NMTK — audit of the Braille replication + a known-good target

Date: 2026-07-28
Follows: `current tasks/2026-07-18/braille-replication-handoff.md`

## 1. Braille audit result: the guide was followed correctly

`workspaces/to-test.nmtk` was checked against Guide 2 in
`current tasks/2026-07-17/snntorch_cnlstudio_replication_guide.md`, the live codegen
(`neurocnl/backend/app/routers/notebook.py`), the last generated notebook
(`workspaces/pipeline_snntorch_sim.ipynb`), and `paper/03_rnn/Braille_training_snntorch.ipynb`.

Structurally correct — the generated `Net` matches the reference `model_build()` line for line
(`reset_delay=False`, `bias=None` on both Linears and on `lif1.recurrent`, fast_sigmoid slope 5,
seed 42, deterministic algorithms). The L1/L2 regularizers resolve to `hid_rec` (hidden spikes),
same formula as the reference, despite the alarming `# ponytail: target_layer=… does not match a
known variable` comment. Checkpoint tie-break `>=` on `val_accuracy` matches the reference.

Deviations found:

| # | Finding | Impact |
|---|---|---|
| 1 | Pipeline Settings `epochs = 350`; guide/reference/known-good all say 500. The `validationLoop` node's own stale `epochs: 500` is deliberately ignored (`notebook.py:2022`). | Real — undertrained. |
| 2 | Val + Eval Data Loader `shuffle: true`; guide says false. | None — both hardcoded `False` downstream (`notebook.py:2761`, `:2725`). |
| 3 | Pipeline Settings say `mse_count` / `batch_size 32`; canvas says CE Count Loss / 64. | None today (canvas wins) but two knobs silently disagreeing. |
| 4 | Gradient Clip + ReduceLROnPlateau exist in neither the reference nor the guide. | Deliberate additions (77.86%→80%), not part of the replication. |

Not reproducible across runs regardless: 80% → 67.86% → 42%. Braille is a poor debugging surface —
500 epochs/run, 2,360 params, 140 test samples (1 sample = 0.71%), recurrent `snn.RSynaptic` on a
known 0.9.x→1.0.0 breaking change, and no train-accuracy signal emitted.

**Unresolved, 2-minute check before rebuilding Braille:** the eval cell prints either
`Loaded best checkpoint from best_model.pt` or `best_model.pt not found — evaluating with current
in-memory weights`. If the 42% run printed the second, that number is the final-epoch model, not
the best one — and with ReduceLROnPlateau over 500 epochs the gap is easily that large.

## 2. Decision: build a known-good baseline first

snnTorch Tutorial 5 FCN on MNIST. Trains in minutes, uses the simplest codegen path (feedforward,
no recurrence), and answers "is NMTK's training pipeline sound?" unambiguously.

## 3. Codegen facts established (don't re-derive)

- **`weight_fill` is irrelevant to training.** Weights are lost in the CNL-text round trip (the
  sentence records only the shape), so `notebook.py:722` always takes the `np.all(w == 0)` branch
  and every `nn.Linear` gets PyTorch default init.
- **`cnl.Leaky` cannot take static input.** It's in `_recurrent_kinds` (`notebook.py:954`) → the
  time-series forward (`x.swapaxes(0,1)`). A `(B, 784)` batch becomes `(784, B)` and the Linear
  fails. Static features need `nir.LIF`, which takes the non-recurrent branch with
  `x.unsqueeze(0).expand(globals().get('num_steps', 1), -1, -1)` (`notebook.py:1124`).
- **`nir.LIF` has no `beta` in the CNL grammar** — only `tau`. beta is back-computed as
  `1 - dt/tau`, `dt` defaulting to `1e-4`. `tau = 0.002` → β = 0.95. It also emits
  `reset_mechanism='zero'`, where `cnl.Leaky` emits `'subtract'`.
- **`num_steps` has a silent fallback of 1.** A static-input model evaluated without the training
  cell having run in the same kernel uses one timestep and collapses to chance, no error raised.
- `load_best_checkpoint` defaults to `True` when absent from the node (`notebook.py:2602`).
- `nir.Linear` drops bias (`notebook.py:735`); `nir.Affine` keeps it.
- **A val-only Data Loader used to clobber `train_loader`** (fixed 2026-07-28). Every setup
  node's generic `_dag_node_code` ran, including the loader wired only to
  `validationLoop.val_data`; `_pt_loading_code` always binds `train_loader`/`test_loader`, so
  the val loader — emitted second — overwrote the training set with the validation set.
  `_training_phase_to_code` now skips the generic pass for a val-only loader, guarded on
  another loader existing in the phase. `_pt_val_loading_code`'s docstring had named this
  hazard all along; only the exclusion was missing.
- **`backend/app/schemas/pipeline_dag.py` stopped re-exporting `_LOADER_TYPES`,
  `_LOSS_TYPES`, `_OPTIMISER_TYPES`, `_SCHEDULER_TYPES`** in commit `74957390` while
  `notebook.py:22` still imported them from there — so `import
  backend.app.routers.notebook` raised `ImportError` and the whole notebook router was dead
  on that commit. Restored 2026-07-28. Worth re-checking after any `dag_schema` move.

## 4. Data

`current tasks/2026-07-28/prepare_mnist_pt.py` → `workspaces/`. Verified to load through the exact
`_pt_loading_code` path (`weights_only=True` inside `safe_globals([TensorDataset])`), all 10 classes
present in each split.

| File | Shape | Size |
|---|---|---|
| `mnist_train.pt` | (9000, 784) | 28.3 MB |
| `mnist_val.pt` | (1000, 784) | 3.1 MB |
| `mnist_test.pt` | (2000, 784) | 6.3 MB |

Validation is carved out of the train split, so the test set stays untouched by best-checkpoint
selection. Subset keeps an epoch at ~1–2 min; raise `N_TRAIN`/`N_TEST` in the script for full MNIST.

## 5. Recipe, and the numbers it actually produces

`784 → Linear(1000) → LIF(β=0.95) → Linear(10) → LIF(β=0.95) → 10`, 25 timesteps, batch 128,
Adam lr=5e-4, CE Count Loss, fast_sigmoid slope 25, 5 epochs. **No** Gradient Clip, ReduceLROnPlateau,
or spike regularizers — none are in the tutorial, and a baseline should have nothing to blame.

Measured by hand-mirroring the exact generated code against the exact `.pt` files (seed 42):

| epoch | train loss | val acc (no bias) | val acc (bias) |
|---|---|---|---|
| 1 | 0.9241 | 89.40% | 90.70% |
| 2 | 0.2475 | 93.00% | 92.90% |
| 3 | 0.1692 | 93.00% | 93.40% |
| 4 | 0.1408 | 93.10% | 94.00% |
| 5 | 0.1012 | **95.00%** | **94.70%** |
| 6 | 0.0711 | 94.30% | 94.40% |

**Test: 92.45% (`nir.Linear`) vs 92.90% (`nir.Affine`)** — 9 samples out of 2000, noise. Use
`nir.Linear`. Val peaks at epoch 5 and dips at 6, so 5 epochs is right. Output spike rate ~0.04.

## 6. Next

1. Build the graph in the Studio per the plan; confirm the generated notebook shows
   `snn.Leaky(beta=0.950000, …)`, `lr=0.0005`, `range(5)`, and `num_steps = 25` bound before
   `net(data)`.
2. ~~Compare the Studio's test accuracy against the 92.45% above.~~ **Done — it read 82.25%,
   and the cause is found.** The generated train cell bound `train_loader` twice, the second
   time to `mnist_val.pt`, so the run trained on 1000 samples and validated on the same 1000
   (95.8% "val" = train accuracy). Proof needs no re-run: every train-phase output spike rate
   is an exact integer over `25 × 104 × 10` — a 104-sample final batch, and `1000 % 128 = 104`
   where `9000 % 128 = 40`. Fixed in §3 above; re-generate and expect ~92.5%.
3. Only then return to Braille: run the `best_model.pt` check in §1, then rebuild as bare reference
   (Adam 1e-3, 500 epochs, batch 64, no clip, no scheduler) and re-add the two stability nodes one
   run at a time.
