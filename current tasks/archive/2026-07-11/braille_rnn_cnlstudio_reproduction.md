# Braille RNN CNLStudio reproduction — merged to `neurocnl` dev

Merged `agents/braille-rnn-cnlstudio` → `dev` (fast-forward, `c6480af0`), 25 commits.

## Problem

Two issues: (1) the Training tab's Data Loader inspector lost/cross-assigned parameter values on sequential edits, and (2) the node-based Training DAG canvas was entirely decorative — editing Adam/Surrogate-Backward/L1-L2 node parameters never reached the backend, which trained a hardcoded non-recurrent model with no validation, checkpointing, or NIR-RSynaptic fidelity, making the reference Braille-letter-reading RNN notebook (12→40→7, recurrent, 256 timesteps, 500 epochs, 90–94% accuracy) unreproducible through the UI.

## Solution (9 plan tasks + 1 critical follow-up)

Fixed the parameter-loss bug (provider merge + single-key commits), added NIR-import fusion (CubaLIF+self-loop-Linear → `cnl.RSynaptic`/`Synaptic`), wired the Training DAG into `/training/run`, built a real recurrent mini-batch trainable model with the exact reference loss formula, added validation/best-checkpoint/eval-reload, and added frontend node types (Validation Loop, eval-mode indicator, JSON hyperparameter import, Dynamics spike-raster fix). A final whole-branch review caught that the frontend never actually *sent* the DAG/architecture graph to the backend at all (Task 9) — fixed as the last commit, since without it the whole engine was unreachable from the UI despite being correctly built and tested.

## Verification and restart

Backend: `PYTHONPATH=. pytest neurocnl/tests/ backend/tests/` — 655 passed vs. 619 pre-branch baseline, 39 failed vs. 41 baseline (net improvement, zero regressions; remaining failures are pre-existing/unrelated, see plan file). Frontend: `flutter test` — 1459 passed, 12 pre-existing/unrelated failures. To try the actual workflow: import `paper/03_rnn/braille_noDelay_noBias_subtract.nir`, use JSON Import Config with `paper/03_rnn/data/parameters_noDelay_noBias_ref_subtract.json`, configure Data Loader/Time Loop/Validation Loop, and run training — no server restart needed beyond the normal `neurocnl` backend/frontend dev-server reload.

Full plan and task-by-task detail: `/Users/yoshimartodihardjo/.claude/plans/fix-cnlstudio-so-the-jolly-donut.md`.

## Known follow-ups (spawned as background tasks, not blocking)

- `task_0fe8e2d0` — edge-parameter inspector has the same blind-replace bug just fixed for node parameters.
- `task_42c6b1ac` — `checkpoint_metric`/`checkpoint_mode` UI dropdowns are silently ignored by the adapter (always compares val_accuracy/max, matching the reference notebook's default, but a user-selected alternative has no effect and no warning).
