# Feature: View + stop all running Jupyter tasks (step 5 & step 6)

## Problem
Step 5 ("Notebook") embeds JupyterLab in a WebView where the user manually
runs notebooks (raw kernel sessions, tracked only by the Jupyter server
itself). Step 6 ("Run") queues automated training via `POST
/api/notebook/run`, tracked in `job_store` (SQLite) — but there was no UI
surface showing what's currently running, and no way to actually stop either
kind: `_stopTraining()` in `run_step.dart` only cancelled the client-side SSE
subscription while the server kept executing.

## Fix
**Backend — worker** (`workers/jupyter_server/nmtk_env_manager/`):
`JobRegistry` (`jobs.py`) gained `register_kernel()`/`cancel()`, storing the
live `KernelManager` per job so it can be `shutdown_kernel(now=True)`'d on
demand; `_execute_notebook_job` (`handlers.py`) now registers its kernel, and
`JobHandler` gained `DELETE` to trigger the cancel.

**Backend — neurocnl** (`neurocnl/backend/app/`): `job_store.py` gained
`platform`/`notebook_path` columns (idempotent `ALTER TABLE`, same pattern as
the existing `request_id` migration) and `list_active_notebook_jobs()`.
`kernel_runner.py` gained `GET /notebook/jobs/active` (poll target),
`POST /notebook/jobs/{id}/cancel` (cancels the local asyncio task, forwards a
`DELETE` to the worker's job when execution was delegated there, and marks
the job `failed` with `"Cancelled by user"`), and a native-Jupyter-session
proxy — `GET /notebook/sessions` / `DELETE /notebook/sessions/{id}` — covering
step-5's manually-run kernels, which aren't job_store jobs at all. Confirmed
via `suite_api/domains/neurocnl/router.py` that `kernel_runner.router` is
mounted in-process under `/api/neurocnl/*`, so no suite_api changes were
needed (the plan initially assumed otherwise; corrected after reading the
mount).

**Frontend** (`neurocnl/frontend/lib/`): `api_client.dart` gained the four
matching client methods. New `providers/running_notebook_tasks_provider.dart`
(`AsyncNotifier`, 3s `Timer.periodic`, re-entrancy guard — same shape as
`ModuleNotifier` in nmtk's launcher) merges both sources into one polled list
and exposes `.cancel(task)`. `studio_top_bar.dart` gained
`_RunningTasksIndicator` — a badge next to the autosave indicator, hidden when
nothing is running, opening an `AlertDialog` list with a Stop button per task
— visible regardless of which step is active, satisfying "poll the server,
show both step 5 and step 6 tasks, make both stoppable."

## Verification
- `ruff check` / `ruff format --check` / `mypy`: clean on all touched Python
  files.
- `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest -p asyncio backend/tests/test_kernel_runner.py
  backend/tests/test_job_store_service.py`: 31/31 pass. (Plain `pytest` in
  this environment fails to *collect* — a pre-existing, unrelated
  `pytest-nengo`/`matplotlib` circular-import break in this machine's conda
  env; confirmed by reproducing it on an untouched test file too.)
  `test_jobs_router.py` has 4 pre-existing failures unrelated to this change
  (calls `set_complete()` without `set_running()` first, which the untouched
  guard clause has always rejected) — same 4 fail with or without this diff.
- `flutter analyze` on all 4 touched Dart files: 0 new issues (pre-existing
  unrelated warnings in `studio_screen.dart` only).
- Not yet exercised end-to-end against a live `docker-ex-m` deploy (no dev
  server driven this session) — before calling this fully done: start a Run
  from step 6 and a manual cell from step 5, confirm both show up in the
  top-bar dropdown within ~3s, and that Stop actually halts each one on the
  server.

## Incident: accidental `git stash pop` in the `neurocnl` submodule
While A/B-testing, ran `git stash push`/`pop` from inside the `neurocnl`
submodule (cwd had drifted there from an earlier `cd`) with superproject-style
paths that didn't match anything; the `push` silently stashed nothing, and the
follow-up `pop` instead applied a **pre-existing, unrelated** stash
(`"pull-all.sh auto-stash before pull"`, dated 2026-07-02) already sitting in
that submodule, producing a merge conflict in
`frontend/macos/Flutter/GeneratedPluginRegistrant.swift`. Stopped immediately,
confirmed the stash was still intact (not lost), and asked the user how to
proceed rather than auto-resolving. Per the user's answer (drop stashes older
than 3 days), reverted the stale stash's contribution to all 3 affected files
(`GeneratedPluginRegistrant.swift`, `network_canvas.dart`, `pubspec.yaml` —
verified each back to bit-identical with `HEAD` via `git diff HEAD`) and
dropped the stash. No user content was lost; nothing outside those 3 files
was touched by the incident.
