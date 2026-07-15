# Fix: `loss_val.backward()` grad_fn error + missing validationLoop codegen

## Problem
User reported `RuntimeError: element 0 of tensors does not require grad and does not have a grad_fn`
on `loss_val.backward()` in a notebook generated from their NeuroCNL pipeline canvas
(`workspaces/session.neurocnl-workspace.json`). Root cause traced to two real bugs in
`neurocnl/backend/app/routers/notebook.py`'s codegen, not user error:

1. The `surrogateBackward` pipeline node emitted `spike_grad = surrogate.fast_sigmoid(...)` in the
   **Train cell**, with its own comment admitting it "must be passed to neuron constructors above" —
   but those constructors live in an earlier, separate **Architecture cell** (`_generate_snntorch_code`)
   and never received `spike_grad=`. Cross-cell wiring gap, not fixable by DAG node reordering.
2. `validationLoop` had no codegen at all (`# validationLoop — no code generator defined`), so
   early stopping monitored training loss instead of real held-out validation loss.

## Fix
- Threaded `spike_grad_expr` from the `surrogateBackward` DAG node through
  `_build_v2_notebook` → `_generate_arch_code` → `_generate_snntorch_code`, so every spike-producing
  neuron constructor (`nir.LIF`/`CubaLIF`/`IF`, `CnlRSynaptic`/`Synaptic`/`RLeaky`/`Leaky`) receives
  `spike_grad=spike_grad` when a `surrogateBackward` node is present. `_dag_node_code`'s
  `surrogateBackward` case shrunk to just `loss_val.backward()` (no longer recreates spike_grad).
- Implemented `validationLoop` codegen: setup vars via `_dag_node_code`, a dedicated
  `_val_loader_code`/`_pt_val_loading_code` pair that binds `val_loader` without clobbering
  `train_loader`/`test_loader`, and a real per-`every_n_epochs` validation pass in
  `_training_phase_to_code`'s `epoch_tail` (checkpoint tracking, `best_model.pt` save,
  and `earlyStopping` now checks real `val_loss` instead of training `avg_loss` when both are present).
- Fail-fast: `save_best_checkpoint=True` with no `val_data` loader wired now raises `ValueError` at
  codegen time instead of silently skipping validation.
- Removed `validationLoop`'s own `epochs` parameter (frontend `pipeline_dag.dart` +
  `pipeline_node_property_panel.dart`) — it diverged from the outer pipeline's `epochs` (500 vs 50 in
  the real workspace file). Outer `config["epochs"]` is now the sole source of truth.
- `neurocnl/neurocnl/training/dag_topology.py`: added `"validationLoop"` to `classify_phase`'s
  setup-node types (same bucket as `earlyStopping`).

## Verification
- `PYTHONPATH=. pytest -p no:nengo backend/tests/test_notebook_codegen.py backend/tests/test_notebook_generate_v2.py`:
  135 passed (9 new tests added), 3 pre-existing unrelated failures (broken torch C-ext install,
  missing `.nir` fixture file — confirmed identical on baseline via `git stash`).
- Full `backend/tests/` suite: identical 52 failed / 38 errors on baseline and after this change
  (all pre-existing/unrelated); passed count increased by exactly the 9 new tests, zero regressions.
- `ruff check` clean on all touched Python files. `ruff format`/`mypy --strict` both hit pre-existing
  environment issues (format debt predates this change; mypy crashes on an unrelated `transformers`
  package under this machine's mypy 1.10.0 — reproduces identically on baseline).
- `flutter test test/models/pipeline_dag_test.dart test/widgets/canvas/pipeline_node_property_panel_test.dart`:
  53/53 passed. `dart format` applied to touched files.

## Cross-file invariant note (for GBrain)
`validationLoop`'s `epochs` param removal must stay in sync across:
`frontend/lib/models/canvas/pipeline_dag.dart` (2 default-parameter dicts),
`frontend/lib/widgets/canvas/pipeline_node_property_panel.dart` (UI field removed),
`backend/app/routers/notebook.py` (`_dag_node_code`'s `validationLoop` case must never read `epochs`
from node params — outer `cfg.epochs` is the only source of truth for training loop length).
