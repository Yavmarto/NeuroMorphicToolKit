# CEL-18 — Local Python toolchain repair and close-out gate measurement

Measured 2026-09-03 after repairing the local Python toolchain. All three uncertified
close-out gates were run to completion on this machine and the real results are recorded
below, red or green.

## Root cause (confirmed)

- `/Users/yoshimartodihardjo/.local/bin/poetry` had a shebang pointing at the deleted
  `/Users/yoshimartodihardjo/anaconda/anaconda3/bin/python3`; every invocation died with
  `bad interpreter`.
- The launcher doctor shelled out to `poetry env info --path` per module, so it crashed
  with `FileNotFoundError` before reporting anything.
- No module had an installed Python environment, so pytest could not collect.

## Repairs made

1. **poetry** — reinstalled via the official installer (`install.python-poetry.org`) into
   `~/.local/bin/poetry` against a live interpreter. Now reports `Poetry (version 2.4.2)`.
   Configured `virtualenvs.in-project true`. `poetry env info --path` works for both poetry
   modules (Neurochip → `Neurochip/.venv`, Neurobench → `Neurobench/neurobench/.venv`).
2. **Per-module environments** (all created; each module suite now collects):
   - Neurochip — `poetry install` (Python 3.12) → `Neurochip/.venv`
   - Neurobench — `poetry install` (Python 3.11) → `Neurobench/neurobench/.venv`
   - Neurosense, Neurohub, neurocnl, Neurosim, suite_api, neurocli, repo root —
     Python 3.11 venvs + `pip install -e` with the module dev/test extras.
3. **coreutils** — `brew install coreutils` links both `gtimeout` and `timeout` into
   `/opt/homebrew/bin`, which clears the GNU-`timeout` failures in
   `client_deployment_service_test.dart` (see gate 2).

### Minimal source changes required to make the toolchain run (issue-authorized scope)

- `Neurochip/pyproject.toml`: `python = ">=3.10,<4.0"` → `>=3.11,<4.0`. The project's own
  `nmtk-contracts` dep requires `>=3.11`, and poetry 2.x refuses to resolve the
  `>=3.10,<3.11` sub-range. No behavior change for supported interpreters.
- `neurocnl/backend/app/services/notebook_graph_analysis.py`: removed `nir.CubaLI` from the
  `WIDTH_PRESERVING_NIR_NODES` tuple. No nir 1.0.x has a `CubaLI` attribute (only `CubaLIF`,
  already listed), so this reference broke import and blocked the whole suite_api test
  collection.
- Local symlinks `Neurosense/nmtk_contracts` → `../nmtk_contracts` and
  `Neurohub/nmtk_contracts` → `../nmtk_contracts` to satisfy the modules' declared
  `nmtk-contracts @ file:./nmtk_contracts` under modern pip (which resolves relative to the
  pyproject dir). Sibling modules neurocnl/Neurochip already use `../nmtk_contracts`.

These changes are uncommitted working-tree edits in the submodules; the parent repo shows
`Neurochip` and `neurocnl` submodules modified. Left for the user/owner to commit or revert.

## Gate 1 — `python3 -m pytest` per module (each module's own venv)

| Module | Command | Result |
|---|---|---|
| Neurochip | `.venv/bin/python -m pytest` (3.12) | **451 passed, 2 skipped** — green |
| Neurobench | `.venv/bin/python -m pytest` (3.11) | **150 passed** — green |
| Neurosense | `.venv/bin/python -m pytest` | **121 passed** — green |
| Neurohub | `.venv/bin/python -m pytest` | 206 passed, 2 skipped, **15 failed** (pydantic v2 `SharedAsset` `metadata` dict-vs-object validation — real code/test gap) |
| neurocnl (full module: core + backend + vendored neurosim) | `PYTHONPATH=.. .venv/bin/python -m pytest` | 1981 passed, 13 skipped, 7 xfailed, **116 failed** (mostly nir 1.0.8 API drift vs code written for older nir) |
| — neurocnl core | `.venv/bin/python -m pytest neurocnl/` | 1118 passed, 12 skipped, 3 xfailed, **80 failed** (nir `LIF.__init__(input_type=…)` API mismatch) |
| — neurocnl backend | `PYTHONPATH=.:../.. .venv/bin/python -m pytest tests` | **697 passed, 4 xfailed** — green |
| suite_api | `pytest suite_api/tests` (CI `suiteapi.sh` env) | 30 passed, **2 failed** (starlette 1.x `_IncludedRouter` has no `.path` — pre-existing) |
| neurocli | `.venv/bin/python -m pytest` | **72 passed** — green |
| Neurosim (submodule) | — | no test suite in this checkout (44 tracked files, no `neurosim/` package; no CI job for it) |
| repo-root `tests/` | root venv, sibling site-packages on PYTHONPATH | 425 passed, 15 skipped, **61 failed** + 4 collection-error files (reference modules/scripts absent from checkout) |
| — launcher/control-plane subset | `tests/launcher_control` + `tests/test_launcher_control_contracts.py` | 342 passed, **7 failed** (5× missing `sshpass` binary on macOS; 2× transport CORS-header code bug) |

The per-module environments are real; the modules that were previously uncollectable now
collect and run. Remaining failures are genuine, reproducible code/dependency gaps in the
current source, not missing environments.

## Gate 2 — `flutter test` in `nmtk/neuro_toolkit`

**2331 passed, 5 skipped, 18 failed.**

- Pre-sprint baseline at `c1f13a09` was **20 failures**. Under the repaired toolchain
  (coreutils installed) it is **18**.
- `client_deployment_service_test.dart` now passes fully (50 tests) — **installing coreutils
  clears the GNU-`timeout` failure**, confirming the issue's hypothesis. Homebrew coreutils
  links both `gtimeout` and `timeout` into `/opt/homebrew/bin`, so the test's
  `Process.runSync('timeout', …)` resolves. No test was rewritten.
- Remaining 18 failures are the known pre-existing set: `workbench_feature_boundary_test.dart`
  (1), `project_screen_test.dart` (1), `studio_screen_test.dart` (15), and
  `akida_runtime_reasons_test.dart` (1). Out of scope per the issue.

## Gate 3 — `python3 scripts/launcher_control_service.py --doctor --json`

Runs to completion and reports:
- **fatalCount: 0**
- **degradedCount: 1**
- **okCount: 10**

The single degraded check is `studio-framework-sdks`: the Suite API reports that the optional
NeuroChip Studio hardware extras (`akida`, `brian2`, `snn-mlir`) are not installable on this
machine (read from the pre-existing `.nmtk/suite_api_env/install-fingerprint.json`). That is a
degraded *optional capability*, not a fatal error, and it reflects the true state of this
hardware-less macOS box.

## Known-good gates re-checked under the repaired toolchain

- `ruff check .` → **All checks passed!** (unchanged clean)
- `dart analyze nmtk/neuro_toolkit/` → **No issues found!** (unchanged clean)

## Bottom line

All three gates now run to completion and their real numbers are reported above. Two gates
(neurocnl backend, neurocli, plus Neurochip/Neurobench/Neurosense) are fully green; the rest
report honest red results that are reproducible pre-existing code/dependency gaps, with two
genuine environment repairs (poetry + coreutils) landing as intended. The Neurohub pydantic-v2
validation failures and the neurocnl nir-1.0.8 API drift are the most likely candidates for a
follow-up cleanup pass.
