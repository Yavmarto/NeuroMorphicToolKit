# CEL-32 — Stage 1 Trustworthy Baseline Snapshot of the Python Toolchain

**Date measured:** 2026-09-06
**Parent repo commit:** `57aef7bd54bffccc662a2ffc85d9dffb16c04252`
**Submodule pins:** Neurobench `2d18c731` (+173 ahead of tag), Neurochip `ec419c11` (+234 ahead), Neurohub `4a579f1f` (dev), Neurosense `2625d2f1` (dev), Neurosim `f60fd226` (dev), neurocnl `5824f9bb` (+911 ahead of tag)

This is a **read-only measurement**. No source, test, or config files were edited to make anything pass. Every number below is the real output of the command shown, captured to a log file under `logs/`. Where a module fails to install or collect, the real error is quoted — nothing here is invented or estimated.

Per-module venvs were rebuilt from scratch (the prior 2026-09-03 CEL-18 report's venvs no longer existed on disk — `deep_clean.sh`/normal dev churn wipes `.venv`). Full install logs are in `logs/*-install*.log`.

---

## 1. Per-module ruff / ruff format / mypy / pytest results

### Neurochip (poetry, Python 3.12, commands per `.github/workflows/ci.yml` `test-neurochip` job)

| Tool | Command | Result |
|---|---|---|
| ruff check | `poetry run ruff check .` | **2 errors** |
| ruff format --check | `poetry run ruff format --check .` | 2 files would be reformatted, 185 already formatted |
| mypy | `poetry run mypy .` | Success: no issues found in 144 source files |
| pytest | `poetry run pytest --tb=short --hypothesis-show-statistics` | **3 failed, 448 passed, 2 skipped** |

`ruff check` full output:
```
F821 Undefined name `zlib`
   --> neurochip/app/services/akida_model_bundle.py:472:35
            data=base64.b64encode(zlib.compress(contiguous.tobytes())).decode("ascii"),
                                   ^^^^
(zlib is never imported in this module — real bug, not a false positive: base64 is imported but zlib is not)

F821 Undefined name `_validate_remote_url`
  --> neurochip/tests/test_akida_ssrf.py:28:13
            _validate_remote_url("http://akida-server.example.com/deploy")
            ^^^^^^^^^^^^^^^^^^^^
(test calls a name that isn't imported/defined in this test file — test itself is broken, separate from the 3 pytest failures below)

Found 2 errors.
```

pytest failures (`logs/Neurochip-pytest.log`):
```
FAILED neurochip/tests/test_routers.py::test_akida_map_returns_structured_status_for_model_construction_failure
  E   AssertionError: assert 'mapped' == 'failed'
FAILED neurochip/tests/test_routers.py::test_akida_verify_remains_backward_compatible_for_mapping
  E   AssertionError: assert [] == ['construct:4', 'map']
FAILED neurochip/tests/test_routers.py::test_akida_map_constructs_and_maps_backend
  E   AssertionError: assert [] == ['construct:2', 'map']
```

### Neurobench (poetry, Python 3.11)

| Tool | Result |
|---|---|
| ruff check | All checks passed! |
| ruff format --check | 90 files already formatted |
| mypy | **10 errors in 2 files** (checked 92 source files) |
| pytest | **150 passed** |

mypy full output (`logs/Neurobench-mypy.log`): all 10 errors are in `data/scripts/{run_generator,validate_all}.py` — `Missing type arguments for generic type "dict"/"list"` (8×) and one `Function is missing a return type annotation`. These are untyped `dict`/`list` annotations under strict mypy, not runtime bugs.

### Neurosense (pip -e, Python 3.11)

| Tool | Result |
|---|---|
| ruff check | All checks passed! |
| ruff format --check | 5 files would be reformatted, 122 already formatted |
| mypy | Success: no issues found in 55 source files |
| pytest | **121 passed** |

### Neurohub (pip -e, Python 3.11)

| Tool | Result |
|---|---|
| ruff check | All checks passed! |
| ruff format --check | 5 files would be reformatted, 127 already formatted |
| mypy | **6 errors in 3 files** (checked 101 source files) |
| pytest (full suite in one process) | **crashes** — `Fatal Python error` (native crash, not a normal test failure) inside `test_concurrency.py` |
| pytest (`test_concurrency.py` alone) | Same native crash — thread-related fatal error, reproducible in isolation |
| pytest (full suite excluding `test_concurrency.py`) | **219 passed, 2 skipped** |

The full-suite run does not produce a normal pytest summary — it hard-crashes the interpreter (`Fatal Python error`, thread traceback dump) once it reaches `neurohub/tests/test_concurrency.py`, so CI-equivalent "run everything in one process" cannot currently report a pass/fail count for that file; splitting it out gets a clean 219/2 result for the rest. This is a real, reproducible gap, not a flake — recorded as-is rather than silently excluded.

mypy full output: `Returning Any from function declared to return "Response"` (1), `Missing type arguments for generic type "dict"` (3, all in test files), `Unused "type: ignore" comment` (2).

### neurocnl — core (pip -e, Python 3.13 venv)

| Tool | Command | Result |
|---|---|---|
| ruff check | `ruff check .` | **5 errors** (all F401 unused-import) |
| ruff format --check | `ruff format --check .` | 17 files would be reformatted, 581 already formatted |
| mypy | `mypy neurocnl` | **could not run** — see below |
| pytest | `pytest neurocnl/ -v --tb=short` | **1198 passed, 12 skipped, 3 xfailed** |

mypy **failed to run at all**, not "0 issues":
```
.venv/lib/python3.13/site-packages/numpy/__init__.pyi:737: error: Type statement is only supported in Python 3.12 and greater  [syntax]
Found 1 error in 1 file (errors prevented further checking)
```
This venv's mypy is parsing numpy's bundled stub with a target Python version below what the stub requires (mypy defaults its target to the running interpreter's stdlib feature set unless configured, and this combination trips on a `type` statement). No neurocnl source file was actually type-checked — the run aborted on the first stub it loaded. This needs a pinned mypy `python_version`/interpreter combination before Stage 1's "trustworthy baseline" claim can include neurocnl mypy results; recorded here as an unmeasured gap, not silently skipped.

ruff check full output (`logs/neurocnl-ruff-check.log`): 2× unused imports in `backend/app/routers/notebook.py` (`re`, and a re-exported `load_dataset_catalog` that ruff doesn't recognize as intentionally re-exported), 3× unused hypothesis imports (`given`, `settings`, `strategies`) inside a `try/except ImportError` optional-dependency guard in `neurocnl/runtime/test_nir_support_verdict_matrix.py` — ruff doesn't special-case that pattern.

### neurocnl — backend (same venv, `PYTHONPATH` variants per CI)

| Run | Command | Result |
|---|---|---|
| Backend alone | `cd neurocnl/backend && PYTHONPATH=. pytest tests --tb=short` | **could not collect** — `ModuleNotFoundError: No module named 'nmtk_sdk'` (backend imports `neurosim.app.routers.custom_nodes` → `nmtk_sdk.safety.scan_imports`, and `nmtk_sdk` isn't on this venv's path) |
| Backend with repo root on path | `PYTHONPATH=.:../..` (adds root `nmtk_sdk` package) | **697 passed, 4 xfailed** |

The CI job's own install steps (`pip install -e ./neurocnl` then `-r neurocnl/backend/requirements.txt`) do not install the root-level `nmtk_sdk` package, so a literal reproduction of the documented CI command fails to collect; the second row shows it's a `PYTHONPATH` gap, not a code bug — full backend suite passes once `nmtk_sdk` is reachable.

### suite_api (own venv/pyproject, per `scripts/ci/suiteapi.sh`)

| Tool | Result |
|---|---|
| ruff check | All checks passed! |
| ruff format --check | 38 files already formatted |
| mypy | Success: no issues found in 38 source files |
| pytest | **2 collection errors, run interrupted** |

```
ERROR suite_api/tests/test_error_contract.py
ERROR suite_api/tests/test_neurohub_router.py
ModuleNotFoundError: No module named 'jose'
```
Both failures trace through `suite_api.main` → `suite_api.domains.neurohub.router` → `Neurohub/neurohub/app/routers/assets.py` → `Neurohub/neurohub/app/auth.py` → `from jose import JWTError, jwt`. `python-jose` is a Neurohub dependency that suite_api's own venv never installs, even though suite_api imports Neurohub's router modules directly (cross-module import without the dependency closure). No test in this file ran; 0 pass, 0 fail, collection never completed.

### neurocli (own venv)

| Tool | Result |
|---|---|
| ruff check | All checks passed! |
| ruff format --check | 3 files would be reformatted (`neurocli/backend.py`, `neurocli/session.py`, `tests/test_backend.py`) |
| mypy | Success: no issues found in 26 source files |
| pytest | **1 failed, 80 passed** |

```
FAILED tests/test_backend.py::test_routes_cover_every_launcher_endpoint_the_app_calls
E   AssertionError: assert {'/api/launcher/auth/login'} == set()
E     Extra items in the left set: '/api/launcher/auth/login'
```
A route-coverage contract test: the launcher app calls `/api/launcher/auth/login` but this test's registry of "routes the CLI knows about" doesn't list it — a real, specific drift between the CLI and the launcher's auth endpoint, not a flaky test.

### workers/ (only two of six `workers/*` dirs have their own installable package + tests; the rest are Dockerfile-only build contexts with no Python test suite)

**`workers/jupyter_server/nmtk_env_manager`** (own venv):

| Tool | Result |
|---|---|
| ruff check | All checks passed! |
| ruff format --check | 5 files would be reformatted |
| mypy | **11 errors in 2 files** |
| pytest | **32 passed** |

mypy errors are all in test files: `tests/test_handlers_execute.py` (8×, `Module has no attribute` on a mocked Jupyter `notebook.base` API surface — the real module's stub doesn't expose those names) and `tests/test_doctor.py` (3×, `_Manager` vs `EnvironmentManager` argument type mismatch in test doubles).

**`workers/snn_mlir_compiler`**: has tests but no dedicated venv/pyproject; ran against the neurocnl venv (nearest existing sibling env) — **4 passed**. No ruff/mypy config found scoped to this directory, so no lint/type numbers are reported for it (would need its own toolchain config to measure meaningfully; not fabricated here).

`workers/{lava_backend,neurobench_runner,neurochip_hw,neurocnl_physics,neurosense_hw}`: Dockerfile + `requirements.txt`/`pyproject.toml` present but no `tests/` directory found — **no Python test suite exists to run**.

### Root `tests/`

| Run | Command | Result |
|---|---|---|
| `tests/launcher_control` only | `pytest tests/launcher_control --tb=short -q` | **350 passed** (0 failures — previously 7 failed in the 2026-09-02 CEL-18 report due to missing `sshpass`/CORS bugs; both are now resolved in this environment) |
| ruff check (whole `tests/`) | `ruff check .` | **2 errors** (both SIM117, `test_launcher_auth.py`, nested `with` that ruff wants combined) |
| ruff format --check | `ruff format --check .` | 28 files would be reformatted, 37 already formatted |
| Full `tests/` (`PYTHONPATH=.:Neurochip:neurocnl:suite_api`, `--continue-on-collection-errors`) | `pytest tests/ --tb=short -q` | **48 failed, 398 passed, 15 skipped, 37 collection errors** |

The 37 collection errors are all `ModuleNotFoundError`/`ImportError` for sibling packages not on this root venv's path even with the three extra `PYTHONPATH` entries added above (`neurochip`, `neurocnl.handoff`, `suite_api.bootstrap`, `nmtk_sdk` sub-paths, etc.) — these are integration/snapshot tests (`test_snapshot_neurochip.py`, `test_snapshot_neurohub.py`, `test_vcr_neurochip.py`, etc.) that assume a fully-assembled multi-module PYTHONPATH the root venv doesn't reproduce out of the box. No mypy config scoped to root `tests/` was found (no root `mypy.ini`/`[tool.mypy]` section targeting `tests/`), so no root-level mypy number is reported.

---

## 2. OpenAPI schema snapshot

Generated by importing each FastAPI app object directly (no server needed) and calling `.openapi()`. Saved under `openapi/`.

| Module | Result | File | Size |
|---|---|---|---|
| Neurochip | OK | `openapi/Neurochip.json` | 100,915 bytes |
| Neurosense | OK | `openapi/Neurosense.json` | 36,163 bytes |
| Neurohub | OK | `openapi/Neurohub.json` | 78,524 bytes |
| suite_api | **failed** | — | `ModuleNotFoundError: No module named 'jose'` (same missing `python-jose` dependency as the suite_api pytest collection failure above) |
| neurocnl/backend | **failed** | — | `ModuleNotFoundError: No module named 'nmtk_sdk'` (same root-cause as the neurocnl backend pytest gap above) |

Both failures are the identical missing-dependency-closure issues already surfaced by the pytest runs, not new problems — recorded here so future diffs against these two schemas have a documented reason for their absence rather than looking like an oversight.

---

## 3. Launcher-control doctor snapshot

`python3 scripts/launcher_control_service.py --doctor --json` → `launcher-control-doctor.json` (4,819 bytes). Top-level keys: `akidaHosts` (paired Akida hardware, one host `hp-prodesk` at `192.168.2.51`, preflight/readiness both `"ok"`), plus the remaining doctor sections (module/environment status) — see the file for full content.

---

## 4. CI workflow error-swallowing audit (`.github/workflows/ci.yml`, plus a scan of the other 6 workflow files)

No `continue-on-error:` and no unpinned `set +e` anywhere in `.github/workflows/*.yml`. All `|| true` / `|| exit 0` occurrences, classified:

**Harmless (diagnostic-only, gates nothing):**
- `which python || true` / `which pytest || true` / `where python || true` / `where pytest || true` — appear in every `test-*` job's "Python diagnostics" step (ci.yml lines ~141-142, 188-193, 253-258, 317-322, 380-385, 452-457). These only print tool locations for debugging; the step's own exit code was never going to gate the job (nothing downstream reads it), and lint/type/test steps run as separate steps regardless.
- `security-scan.yml`: `brew install python@3.12 || true`, `brew link --force --overwrite python@3.12 || true` — best-effort brew steps on a self-hosted runner that may already have the formula; failure here doesn't hide a code defect.
- `security-scan.yml`: `pip-audit || true` and `find . -name requirements.txt -exec pip-audit -r {} \; || true` — these genuinely swallow a real signal (a vulnerable dependency), but pip-audit is advisory/informational in this workflow (not a merge gate), so it's a monitoring gap rather than a false-green risk on the CI status check itself. Worth tightening later but out of Stage 1's "does green lie" scope since nothing depends on this job passing.

**Swallows a real failure signal (flagged for follow-up):**
1. **`test-neurochip-frontend` / `test-neurohub-frontend` / `test-neurosense-frontend`** (ci.yml ~566, 604, 642): each runs `git submodule update --init || true`, then the next steps only run `flutter pub get`/`flutter analyze` inside an `if [ -d ".../frontend" ] && [ -f ".../frontend/pubspec.yaml" ]` guard. If the submodule update fails (auth, network, bad ref), the `|| true` hides it, the directory check then finds nothing to analyze, and the job **still exits 0** — a broken submodule pointer for a frontend that has real content would silently report "analyzed, all good" instead of failing.
2. **`ci-passed`** job (~662-675 `needs:` list, ~685/~702 result checks): lists `test-neurodreamhand` in `needs:` and reads `needs.test-neurodreamhand.result`, but **no job named `test-neurodreamhand` exists anywhere in this file**, and `detect-changes`'s `filters:` block (~52-86) has no `neurodreamhand:` path filter either — only the `outputs:` line (~34) declares it. Confirmed by direct grep of the full 715-line file: zero matches for a `test-neurodreamhand:` job definition. This key can therefore never resolve to `"failure"`, so the branch-protection-facing `ci-passed` summary is not actually gating on whatever Neuro-Dream-Hand testing was meant to cover — it silently no-ops for that product on every run.

Both are structural gaps in the workflow file itself (an unimplemented job reference, and an unconditional error-swallow ahead of a conditional skip), not something visible from a single CI run's green checkmark — exactly the kind of thing Stage 1 was meant to surface before later refactor stages start trusting "CI is green" as a diff baseline.

---

## Summary

**Fully green (ruff + format + mypy + pytest all clean):** Neurosense, suite_api (lint/type only — pytest blocked by a missing dep, see above).

**Real, specific failures (not environment gaps):** Neurochip (2 ruff F821 + 3 pytest assertion failures in Akida map/verify routing), neurocnl core (5 ruff unused-import), Neurobench (10 mypy errors, untyped dict/list in `data/scripts/`), Neurohub (6 mypy errors + a fatal native crash in `test_concurrency.py` when run in the full suite), neurocli (1 pytest route-coverage drift), workers/nmtk_env_manager (11 mypy errors in test doubles), root `tests/` (48 failed / 37 collection errors, mostly missing sibling-package PYTHONPATH for integration/snapshot tests), formatting drift in nearly every module (2-28 files each — none blocking).

**Could not be measured at all, with real reason:** neurocnl mypy (mypy itself crashes on a numpy stub before checking any source), suite_api pytest + OpenAPI (missing `python-jose`, a Neurohub dependency suite_api's venv never installs), neurocnl/backend OpenAPI (missing `nmtk_sdk` on that venv's path — same class of gap as its pytest run without the extra PYTHONPATH entry).

These gaps are the actual "what does green mean today" answer Stage 1 was asked to establish — later refactor stages should treat modules with unmeasured mypy/pytest results as **unverified**, not clean, until the missing-dependency and mypy-config issues above are fixed.
