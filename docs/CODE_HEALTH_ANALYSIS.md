# Code Health Analysis

Date: 2026-04-08

## Scope

This audit is limited to code-health signals from project-configured static analysis and type-checking:

- Flutter/Dart: `flutter analyze`
- Python linting: `ruff check .`
- Python typing: `mypy .`

I ran those checks from each discovered project root that has `pubspec.yaml`, `analysis_options.yaml`, or `pyproject.toml`. I did not run ad hoc linting against documentation-only folders or infrastructure directories without a project-level analyzer configuration.

## Executive Summary

- One remediation pass is complete. The highest-value breakages from the initial audit have been reduced substantially.
- Flutter health is now clean across the audited packages: `Neurosense/frontend`, `nmtk_ui_core`, `nmtk/neuro_toolkit`, `Neurobench/frontend`, `Neurohub/frontend`, `Neurosim/frontend`, `Neurochip/frontend`, and `neurocnl/frontend` all pass `flutter analyze`.
- Python health improved materially:
  - `Neurobench/neurobench` is now clean
  - `Neurosense` is now clean under Ruff and mypy
  - `Neurochip` is now clean under Ruff and mypy
  - `neurocnl` is now clean under Ruff and mypy
  - `Neuro-Dream-Hand` is now clean under Ruff and mypy
  - `Neurosim` is now clean under Ruff and mypy, and its duplicate Python tool config has been consolidated
- There are no active code-health findings left in the audited packages from this pass.

## Flutter / Dart Findings

### Clean targets

- `Neurobench/frontend`: `flutter analyze` passed with no issues.
- `Neurohub/frontend`: `flutter analyze` passed with no issues.
- `Neurosim/frontend`: `flutter analyze` passed with no issues.
- `Neurochip/frontend`: `flutter analyze` passed with no issues.

### `nmtk_ui_core`

Result: clean after remediation

Fixes applied:

- replaced dangling top-of-file doc comments with non-library comments
- converted internal relative imports to `package:` imports
- added the missing empty-list typing in tests

Current status:

- `flutter analyze`: passed with no issues

Assessment: resolved in this pass.

### `nmtk/neuro_toolkit`

Result: clean after remediation

Fixes applied:

- converted provider/screen relative imports to `package:` imports
- removed the unnecessary `dart:typed_data` import
- added the missing `const` instances flagged by the analyzer
- removed the unused `_stepIndex` helper
- migrated the Teensy serial-port chooser away from deprecated `groupValue` / `onChanged` radio usage

Current status:

- `flutter analyze`: passed with no issues

Assessment: resolved in this pass.

### `Neurosense/frontend`

Result: clean after remediation

Fix applied:

- added the missing local `nmtk_ui_core` path dependency in `pubspec.yaml`

Current status:

- `flutter analyze`: passed with no issues

Assessment: resolved in this pass.

### `neurocnl/frontend`

Result: clean after remediation

Fixes applied:

- typed the empty collection literals in `test/models_serialization_test.dart`

Current status:

- `flutter analyze`: passed with no issues

Assessment: resolved in this pass.

## Python Findings

### Clean or near-clean packages

#### `Neurohub`

Result:

- `ruff check .`: passed
- `mypy .`: passed, `89` source files checked

Assessment: best code-health baseline in the repo.

#### `Neurobench/neurobench`

Result:

- `ruff check .`: passed
- `mypy .`: passed, `76` source files checked

Fix applied:

- shortened the overlong SpiNNaker2 comment in `app/services/benchmark_runner.py`

Assessment: resolved in this pass.

### Packages remediated in this pass

#### `Neurosense`

Result:

- `ruff check .`: passed
- `mypy .`: passed, `52` source files checked

Fixes applied:

- replaced global stream state in `neurosense/app/routers/prophesee.py`
- replaced global hardware state in `neurosense/pynq_service/main.py`
- extracted connection provisioning helpers in `neurosense/app/services/device_manager.py` to reduce branch complexity

Assessment: resolved in this pass.

#### `Neurochip`

Result:

- `ruff check .`: passed
- `mypy .`: passed, `95` source files checked

Fixes applied:

- removed unused imports and stale `type: ignore` comments
- added missing function and payload annotations across router and service modules
- tightened `dict` typing in contracts/tests
- fixed stale test typing around flash jobs and simulator state assertions
- added a module-level `generate_akida_package()` helper to match the test surface

Assessment: resolved in this pass.

#### `neurocnl`

Result:

- `ruff check .`: passed
- `mypy .`: passed, `228` source files checked

Fixes applied:

- cleaned the small Ruff issues in topology and generator tests
- added the missing local annotations in converter/tests
- fixed the `ParseResult` error-detail typing mismatch in `pipeline.py`
- removed two unrelated `F541` issues surfaced during the rerun

Assessment: resolved in this pass.

#### `Neuro-Dream-Hand`

Result:

- `ruff check .`: passed
- `mypy .`: passed, `54` source files checked

Fixes applied:

- imported `Any` in the gym wrapper tests
- added explicit overlay guards in `hardware/pynq_controller.py`
- removed the local name redefinition in `toolkit_handoff.py`

Assessment: resolved in this pass.

#### `Neurosim`

Result:

- Root project `Neurosim/pyproject.toml`
  - `ruff check .`: passed
  - `mypy .`: passed, `45` source files checked

Fixes applied:

- modernized `app/services/neurocnl_bridge.py` to use `pathlib`, clean import ordering, and remove simplification warnings
- split `app/services/cnl_to_graph.py` into smaller helpers so it passes complexity thresholds
- fixed the remaining cast-style issue in `app/services/components.py`
- fixed the earlier limiter/main/test issues from the first remediation pass
- removed the duplicate nested `Neurosim/neurosim/pyproject.toml`
- merged the previously effective lint/type policy into the root `Neurosim/pyproject.toml`
- updated setup/release docs so the supported tooling entry point is `Neurosim/`

Assessment: resolved in this pass. `Neurosim/pyproject.toml` is now the single supported Python tool config for the module.

## Cross-Cutting Patterns

- The original `Neurosense/frontend` dependency breakage is fixed.
- Most of the Python debt called out in the initial audit was low-risk cleanup rather than deep algorithmic defects.
- The original Dart lint debt was also largely low-risk hygiene: package imports, deprecated widget API usage, test typing, and top-of-file comments.
- Python code health is now broadly clean across the audited backend packages.
- Flutter code health is now broadly clean across the audited frontend/packages.
- The largest remaining engineering risk is no longer static-analysis debt; it is keeping future changes aligned with the now-clean tool baselines.

## Recommended Fix Order

1. Keep `Neurosim/pyproject.toml` as the single source of truth for Python tooling in that module.
2. Re-run the full health pass after future feature work to catch regressions early.

## Commands Run

### Flutter

- `flutter analyze` in:
  - `nmtk_ui_core`
  - `nmtk/neuro_toolkit`
  - `Neurobench/frontend`
  - `Neurohub/frontend`
  - `Neurosense/frontend`
  - `Neurosim/frontend`
  - `Neurochip/frontend`
  - `neurocnl/frontend`

### Python

- `ruff check .` in:
  - `Neurobench/neurobench`
  - `Neurosim`
  - `Neurohub`
  - `Neurosense`
  - `Neurochip`
  - `neurocnl`
  - `Neuro-Dream-Hand`
- `mypy .` in the same Python project roots
