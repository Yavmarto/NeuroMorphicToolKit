# Backend Code Health Plan

Date: 2026-04-26

## Scope

Backend Python health scan across:

- `neurocnl`
- `Neurosim`
- `Neurochip`
- `Neurobench/neurobench`
- `Neuro-Dream-Hand`
- `Neurosense`
- `Neurohub`

## Checks Run

Primary checks:

- `ruff check .`
- `mypy .`

Execution notes:

- Global `ruff` was not available, so checks were run with module-native tooling:
- `poetry run ...` for `Neurochip` and `Neurobench/neurobench`
- `uv run ...` for `Neurohub` and `Neuro-Dream-Hand`
- existing `venv` interpreters plus installed `mypy` for `neurocnl`, `Neurosim`, and `Neurosense`
- `uvx ruff check .` for `neurocnl`, `Neurosim`, and `Neurosense`

## Result Summary

| Module | Ruff | Mypy | Notes |
| --- | --- | --- | --- |
| `neurocnl` | 4 errors | 9 errors | Lint is small and auto-fixable; mypy failures are test/demo decorator typing |
| `Neurosim` | 8 errors | clean | Ruff failures are only in one test helper |
| `Neurochip` | clean | 1 error | Single test typing issue |
| `Neurobench/neurobench` | clean | 63 errors | Largest real typing debt |
| `Neuro-Dream-Hand` | clean | 3 errors | Missing `yaml` stubs only |
| `Neurosense` | clean | clean | No code issues found |
| `Neurohub` | clean | 35 errors | Mostly property-test decorators plus 2 app-layer type mismatches |

## Findings By Module

### `neurocnl`

`ruff`:

- 2 `I001` import ordering issues in `neurocnl/layers/layer1_validator.py`
- 1 `UP037` quoted type annotation in `neurocnl/export/pynq_exporter.py`
- 1 `C420` dict comprehension issue in `neurocnl/converter/sinabs_io.py`

`mypy`:

- 9 `untyped-decorator` errors
- concentrated in:
- `tests/test_install_smoke.py`
- `tests/e2e/test_pipeline_failure_flows.py`
- `neurocnl/handoff/test_neurochip_pynq_handoff.py`
- demo tests under `demos/**`

Assessment:

- Production code health is mostly good.
- Typing debt is almost entirely test-fixture and decorator-related.

### `Neurosim`

`ruff`:

- 8 errors, all in `neurosim/tests/routers/test_components.py`
- rules hit:
- `ANN202` x4
- `ARG002` x2
- `ANN002` x1
- `ANN003` x1

`mypy`:

- clean

Assessment:

- This is a narrow cleanup with no broad backend risk.

### `Neurochip`

`ruff`:

- clean

`mypy`:

- 1 `no-any-return` error in `neurochip/tests/test_pynq_compile.py:40`

Assessment:

- Very small follow-up, isolated to tests.

### `Neurobench/neurobench`

`ruff`:

- clean

`mypy`:

- 63 errors across 16 files
- dominant class: 59 `untyped-decorator`
- additional issues:
- 3 `attr-defined` in `tests/test_neurosense_artifact_service.py`
- 1 `misc` in `app/config.py` (`BaseSettings` typed as `Any`)

Hotspots:

- `cli/__main__.py`
- `app/routers/runner.py`
- `app/routers/synsense.py`
- `app/routers/pynq.py`
- `app/routers/comparison.py`
- `app/routers/benchmarks.py`

Assessment:

- This is the largest real backend typing problem in the repo.
- Most errors are systematic FastAPI or CLI decorator typing gaps, which suggests batchable fixes rather than one-off patching.

### `Neuro-Dream-Hand`

`ruff`:

- clean

`mypy`:

- 3 `import-untyped` errors for `yaml`
- files:
- `neurodreamhand/experiments/config.py`
- `neurodreamhand/experiments/tracking.py`
- `neurodreamhand/experiments/runner.py`

Assessment:

- This is dependency typing hygiene, not application logic debt.

### `Neurosense`

`ruff`:

- clean

`mypy`:

- clean

Assessment:

- No backend code-health remediation required from this pass.

### `Neurohub`

`ruff`:

- clean

`mypy`:

- 35 errors across 6 files
- dominant class: 33 `untyped-decorator`
- real app-layer issues:
- `neurohub/app/routers/dashboard.py:53` passes `list[ActivityEntryDB]` where `list[ActivityEntry]` is expected
- `neurohub/app/routers/assets.py:35` passes `str` where a `Literal[...]` asset type is expected

Hotspots:

- `neurohub/tests/properties/test_workflow_properties.py`
- `neurohub/tests/properties/test_orchestration_properties.py`
- `neurohub/tests/properties/test_bundle_properties.py`
- `neurohub/tests/properties/test_project_properties.py`

Assessment:

- Most issues are test/decorator typing noise, but there are 2 genuine application typing mismatches that should be fixed first.

## Recommended Fix Order

### Phase 1: Fast wins

1. Fix `neurocnl` `ruff` violations with `ruff --fix`.
2. Fix `Neurosim` test helper annotations.
3. Fix the single `Neurochip` test return type issue.
4. Add `types-PyYAML` to `Neuro-Dream-Hand` dev dependencies and re-run `mypy`.

Expected outcome:

- 4 modules move to fully green or near-green with low risk.

### Phase 2: Real application typing mismatches

1. Fix `Neurohub` app-layer mismatches in:
- `neurohub/app/routers/dashboard.py`
- `neurohub/app/routers/assets.py`
2. Fix `Neurobench/neurobench/app/config.py` `BaseSettings` typing.

Expected outcome:

- Eliminate the non-test typing defects before spending time on framework-decorator noise.

### Phase 3: Systematic decorator typing cleanup

Target modules:

- `Neurobench/neurobench`
- `Neurohub`
- `neurocnl` tests and demos

Recommended approach:

1. Identify whether each error comes from FastAPI route decorators, Click/Typer CLI decorators, Hypothesis decorators, or pytest fixtures.
2. Apply a consistent strategy per framework:
- annotate fixtures and test helpers explicitly
- where framework stubs are the root cause, consider targeted `mypy` config relaxation for tests only
- avoid weakening production-package strictness to silence test-only decorator noise
3. Re-run `mypy` after each framework bucket, not after each individual file.

Expected outcome:

- Most of the remaining error volume should collapse quickly because the failures are repetitive.

## Proposed Concrete Work Plan

1. Create a dedicated backend-health branch.
2. Land Phase 1 as one small PR or a few module-scoped PRs.
3. Land Phase 2 as a separate PR focused on real application typing correctness.
4. Land Phase 3 in module-owned follow-ups:
- `Neurobench/neurobench` first
- `Neurohub` second
- `neurocnl` test/demo typing last
5. Add or tighten CI commands so each Python module runs its own `ruff` and `mypy` entrypoints consistently.

## Verification Commands For Follow-up Work

- `cd neurocnl && uvx ruff check . && venv/bin/python -m mypy .`
- `cd Neurosim && uvx ruff check . && venv/bin/python -m mypy .`
- `cd Neurochip && poetry run ruff check . && poetry run mypy .`
- `cd Neurobench/neurobench && poetry run ruff check . && poetry run mypy .`
- `cd Neuro-Dream-Hand && uv run --with ruff ruff check . && uv run --with mypy mypy .`
- `cd Neurosense && uvx ruff check . && venv/bin/python -m mypy .`
- `cd Neurohub && uv run ruff check . && uv run mypy .`

## Bottom Line

The backend is not broadly unhealthy. The main debt is concentrated in typing noise around decorators and test fixtures, with one major hotspot in `Neurobench/neurobench` and a smaller but important app-layer mismatch in `Neurohub`. `Neurosense` is already clean, and several other modules are one small pass away from green.
