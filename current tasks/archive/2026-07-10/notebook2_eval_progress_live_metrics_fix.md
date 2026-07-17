# Notebook 2 (CNN/NMNIST Eval) — Step 6 Run shows no live metrics

Follow-up to `current tasks/2026-07-08/notebook2_eval_progress_fix.md`.

## Symptom

Running Notebook 2's Eval graph through CNLStudio's Step 6 (Run): the run
completes successfully, but the Live Metrics sidebar stays blank the entire
time, only flashing the final accuracy right as the run finishes. Looks
identical to a hang.

## Root cause

The 2026-07-08 fix added a single `_nmtk_emit(...)` call, placed *after* the
eval `for batch_idx...` loop closes, so Step 7 (Results) would see at least
one progress event. That fix was explicitly scoped to "once, not per-batch."
Since `kernel_runner.py`'s `_maybe_publish` only republishes stdout lines
that are already `__nmtk_progress__` JSON, and the notebook never printed
one until the very end, Step 6's Live Metrics sidebar had nothing to render
during the run.

## Fix

Added a second `_nmtk_emit(...)` call inside the eval loop, in
`_phase_dag_to_code` (`neurocnl/backend/app/routers/notebook.py`), right
after the per-batch body runs:

```python
_nmtk_emit(
    epoch=batch_idx + 1,
    total=len(test_loader),
    loss=0.0,
    accuracy=(correct / total if total else None),
    layer_rates={'output': float(spk_out.float().mean().item())},
)
```

This mirrors the training path's per-epoch emit at batch granularity. Uses
`correct`/`total`, already accumulated per-batch by the Accuracy node's
codegen — no new state. The existing post-loop emit (`epoch=1, total=1`,
final whole-dataset accuracy) is unchanged and remains the "run complete"
event Results step keys off.

No changes needed in `kernel_runner.py` or any Dart file — both already
handle repeated `type: "epoch"` events (that's how the training path
streams progress).

Test: `test_eval_phase_emits_nmtk_progress_event` in
`neurocnl/backend/tests/test_notebook_generate_v2.py`, updated to expect
per-batch + final emits instead of exactly one.
