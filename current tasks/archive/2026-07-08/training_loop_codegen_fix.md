# Training-canvas codegen never generated a real epoch/batch loop

Follow-up to [notebook2_eval_progress_fix.md](notebook2_eval_progress_fix.md) and
`current tasks/16 june/cnlstudio_notebook_analysis.md` (Notebook 3: Braille RNN
training).

## Root cause

`_phase_dag_to_code`'s training-phase branch (`neurocnl/backend/app/routers/notebook.py`,
`is_eval=False`) was a flat concatenation of per-node code snippets: no epoch
loop, no batch loop over `train_loader`, and `optimizer.step()` was only ever
emitted as a comment. Generating a Braille-training-style graph (Data
Loader → State Reset → Forward Pass → CE Count Loss → Surrogate Backward →
Adam Optimiser) and executing the generated cell raised
`NameError: name 'data' is not defined`, since nothing ever bound
`data`/`targets` from `train_loader`. Any training pipeline run through
CNLStudio's Step 6 would have failed outright.

## Fix

Added `_training_phase_to_code` (`notebook.py`), which partitions training
nodes into setup (loaders, `timeLoop`, optimiser/scheduler construction,
early-stopping init — run once) versus per-batch body nodes, and wraps the
body in a real `for epoch in range(cfg.epochs): for batch_idx, (data,
targets) in enumerate(train_loader):` loop. The wrapper itself places
`optimizer.zero_grad()`/`optimizer.step()`, `weightClip` (always
immediately post-step), scheduler `.step(...)`, early-stopping's real
`if`/`break` check, and one `_nmtk_emit(...)` progress call per epoch — the
same event shape used by the eval fix, so Step 6 live metrics and Step 7
Results now populate for training runs too.

`adamOptimiser`/`reduceLROnPlateau`/`earlyStopping` node codegen
(`_dag_node_code`) were trimmed to construction/init-only — the loop
wrapper now owns per-iteration/per-epoch placement.

**Deliberate scope decision**: no Validation Loop node or Best Checkpoint
Save exists (confirmed aspirational-only in the analysis doc — no backend
or frontend implementation at all). This fix does not build them. Scheduler
and early-stopping instead monitor epoch-mean **training** loss (marked
`ponytail:` in source, with the upgrade path noted). Held-out accuracy
continues to be measured afterward via the Eval canvas.

Tests: `test_training_loop_is_real_and_runnable` (executes the generated
loop against a stub net/loader — the check that would have caught the
original bug) and `test_training_loop_scheduler_and_early_stopping_are_real`
in `neurocnl/backend/tests/test_notebook_generate_v2.py`. Updated
`test_early_stopping_dag_node` in `test_notebook_codegen.py` to match the
new construction-only contract for that node in isolation.
