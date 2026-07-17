# Notebook edit-detection before Run (Step 6)

## Problem
Step 6 (Run) always called `generateNotebookV2()` again before running, silently overwriting whatever the user had edited in Step 5's embedded JupyterLab view, since both steps write to the same deterministic path (`{workspace_folder}/notebooks/pipeline_{framework}.ipynb`).

## Fix
- Backend (`neurocnl/backend/app/routers/notebook.py`): `GenerateV2Response` now returns `generated_at` (epoch seconds). New `GET /api/notebook/last-modified?workspace_folder=&filename=` reports the notebook's current last-modified time (Jupyter Contents API when a worker is configured, else local file mtime).
- Frontend: new `notebookMetaProvider` (`neurocnl/frontend/lib/providers/notebook_meta_provider.dart`) records `{workspaceFolder, filename, generatedAt}` per platform, written by `notebook_step.dart`'s `_generateAndLoad()`. `run_step.dart`'s `_runSinglePlatform()` checks the last-modified endpoint before regenerating; if the notebook was touched since generation, shows a confirm dialog ("Keep My Edits & Run" vs "Discard & Regenerate") styled on `canvas_screen.dart`'s `_confirmClearCanvas`. Unedited notebooks regenerate silently as before — no extra click in the common case.

## Verification
- Backend: `PYTHONPATH=. pytest backend/tests/test_notebook_generate_v2.py` — 86 passed (2 pre-existing unrelated failures due to a missing fixture file, confirmed present before this change too). `ruff check` clean.
- Frontend: `flutter test test/services/api_client_test.dart` — 8 passed (4 new). `dart analyze` clean for touched files. `dart format` applied. `studio_screen_test.dart`'s 17 pre-existing failures confirmed unchanged against a stashed baseline (unrelated timer-pending issue, not caused by this change).

## Known follow-up (not done)
`notebook_step.dart`'s `ref.listen` block (workspace/spec/platform changes) also silently regenerates while still on Step 5 — same overwrite risk, out of scope here.
