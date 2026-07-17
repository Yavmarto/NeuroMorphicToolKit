# Notebook 2 (CNN/NMNIST Eval) — no live metrics, no spikes, no results

Follow-up to `current tasks/16 june/cnlstudio_notebook_analysis.md` (Notebook 2:
`paper/02_cnn/snntorch_apply.ipynb`).

## Symptom

Rebuilding Notebook 2's Eval-canvas graph (Data Loader → State Reset →
Forward Pass → Accuracy) and running it via CNLStudio's wizard (Step 5
Notebook → Step 6 Run → Step 7 Results): Step 6 reports success, but the
live Metrics/Spikes sidebar stays empty during the run, and Step 7 always
shows "No training results yet. Complete Step 6 (Train) first."

## Root cause

Step 6 always runs the pipeline the same way (generate notebook → execute
via Jupyter kernel → parse stdout for `__nmtk_progress__` JSON lines →
publish as SSE `type: "epoch"` events). The frontend's live sidebar and
`trainingHistoryProvider` (which Step 7 reads) only react to `type == "epoch"`
events. The eval-only codegen path in
`neurocnl/backend/app/routers/notebook.py` (`_phase_dag_to_code`, `is_eval`
branch) only ever printed a plain-text accuracy line — it never called the
`_nmtk_emit(...)` helper already injected into every generated notebook — so
zero progress events were ever published for an eval-only run, even though
the notebook itself ran and printed the correct accuracy.

## Fix

Added one `_nmtk_emit(...)` call right after the eval loop closes in
`_phase_dag_to_code`, in the exact JSON shape `kernel_runner.py`'s
`_maybe_publish` and the Dart `TrainingEpochEvent.fromJson` already expect
(`epoch=1, total=1, loss=0.0, accuracy, layer_rates`). No changes needed to
`kernel_runner.py` or any Dart file. Covers both `evaluation_profile`
values that share this code path (`classification`, `bounded_classification`);
the separate `lif_trace` profile (Notebook 1) is untouched.

Known simplification (marked `ponytail:` in source): `layer_spike_rates`
reflects only the final eval batch, not a full-dataset average. Upgrade
path: accumulate a running sum/count alongside `correct`/`total` if a true
average is needed.

Test: `test_eval_phase_emits_nmtk_progress_event` in
`neurocnl/backend/tests/test_notebook_generate_v2.py`.

## Known separate issue (not fixed here)

The training-phase codegen path (`_phase_dag_to_code`'s `is_eval=False`
branch) is a flat concatenation of node snippets with no epoch/batch loop
and no working `optimizer.step()` call — `data`/`targets` are never bound
outside the eval loop, so running a training pipeline through this path
would likely raise `NameError`. This is unrelated to the progress-emission
bug and needs its own investigation/plan.
