# NMTK Status Audit — 14 Jun 2026
**Auditor:** Claude (Sonnet 4.6)
**Scope:** Root + all Python/backend submodules (mobile/Flutter excluded — in progress)
**Branch:** dev
**Prior audits:** 11-Jun-2026 (Opencode), 16-May-2026 (Claude)

---

## 1. Executive Summary

**Overall POC Readiness: ~83%** (marginal regression from ~85% on 11-Jun)

The overall backend architecture is sound: the suite_api unified proxy is fully wired across all seven module domains (neurocnl, neurosim, neurochip, neurobench, neurosense, neurohub, jupyter), the root docker-compose.yml defines 15+ services with healthchecks, and all root-level CI workflows exist. However, three categories of concrete blockers persist from prior audits:

| Category | Finding | Delta vs 11-Jun |
|----------|---------|-----------------|
| **Ruff violations** | **557 total** (up from 403 on 11-Jun) | Regression — +154 errors |
| **Rogue `print()`** | **21 production print() calls** | Down significantly from 315 — major improvement |
| **Untyped functions** | 113,715 `def` lines without `->` annotation | No change tracked previously |
| **Neurochip frontend** | Still **0 Dart files** — `frontend/` contains only `neurochip.iml` | No change |
| **Hardware export stubs** | BrainScaleS, Lava (hardware), SpiNNaker generators all `raise NotImplementedError` | No change |
| **Neurosim NIR support** | `nir_support.py` has a `raise NotImplementedError` on a live code path | No change |
| **Task fragmentation** | Multiple overlapping tracking systems active | Partially resolved |

**Concrete blockers for POC demo**: Neurochip hardware export (BrainScaleS/Lava/SpiNNaker stubs), Neurochip frontend absence, ruff regression requiring triage.

---

## 2. Linter Snapshot

### Python — Ruff (14-Jun-2026)

Total: **557 errors** (up from 403 on 11-Jun, +38%). 219 auto-fixable (105 additional with `--unsafe-fixes`).

**Top violations by category:**

| Count | Code | Description | Auto-fix? |
|-------|------|-------------|-----------|
| 1,253* | E501 | Line too long (100 > 88) | No |
| 102 | ANN101 | Missing type annotation for `self` | No |
| 101 | UP038 | Use `X \| Y` in isinstance | Yes |
| 65 | W293 | Blank line contains whitespace | Yes |
| 53 | UP015 | Unnecessary open mode parameters | Yes |
| 39 | F401 | Unused imports | Yes |
| 38 | PGH003 | Blanket type-ignore comments | No |
| 30 | E402 | Module-level import not at top | No |
| 21 | E501 | Line too long (101 > 100 — root-level check) | No |
| 21 | I001 | Unsorted imports | Yes |
| 14 | F541 | f-string without placeholders | Yes |
| 4 | F821 | Undefined name `Any` | No |
| 2 | F811 | Redefined unused name (test file duplicates) | No |
| 1 | E999 | **SyntaxError** in `scripts/jules_batch_prompt.py:34` | Manual fix required |

*1,253 E501 count from `--select=E501` run; the 557 total is from default ruleset which excludes some categories.

**Critical finding:** `scripts/jules_batch_prompt.py` has a parse-level SyntaxError that prevents ruff from analyzing it. This file must be fixed or excluded.

**F811 duplicates in tests/test_launcher_control_service.py**: Two test functions are redefined (lines 1032→1247, 1975→2028). One definition silently never runs.

### Print() vs Logging

- **21 production `print()` calls** in non-test, non-pycache Python (down from 315 on 11-Jun — significant improvement)
- **111 `logging.getLogger()` call sites** — ratio now healthy (1 print per 5 logger usages)
- Remaining `print()` are primarily in `scripts/akida_nir_demo.py` (demo script, acceptable) and `neurocnl/backend/app/scratch.py` (scratch file — should be deleted or converted)

### Untyped Functions

- **113,715 `def` declarations** lacking `-> return_type:` annotation across the full repo
- This count includes test files, venv, and non-auditable paths; no per-module breakdown was computed
- No root-level `mypy.ini` found; `Neurohub/mypy_no_plugin.ini` exists with `strict = True`

---

## 3. Task Fragmentation Findings

### Active Tracking Systems

| System | Location | File Count | Status |
|--------|----------|-----------|--------|
| Module `issues/` (open) | `neurocnl/issues/` | 1 file | Active — 1 open issue |
| Module `issues/` (open) | `Neurohub/issues/` | 1 file | Active — 1 open issue |
| `Neurosense/issues-next/` | Neurosense | 4 files | Active — next-sprint queue |
| `tasks/11 june/` | Root `tasks/` | 2 files | Active — recent tasks |
| `issues-archive/` | Root | 51 files | Archival — closed |
| `neurocnl/issues-archive/` | neurocnl | 141 files | Archival — closed |
| `Neurochip/issues-archive/` | Neurochip | 57 files | Archival — closed |
| `Neurohub/issues-archive/` | Neurohub | 42 files | Archival — closed |
| `Neurosense/issues-archive/` | Neurosense | 39 files | Archival — closed |
| `Neurobench/issues-archive/` | Neurobench | 52 files | Archival — closed |
| `docs/unified-dev-pipeline/*/generated-issues/` | docs | 20 files (3 per module) | CDD-generated, planning only |

### Open Issues (verified)

- `neurocnl/issues/15-neurostudio-pipeline-pane-responsive-audit.md` — Flutter responsive audit (mobile scope, active)
- `Neurohub/issues/025-prod-responsive-dashboard-and-bundle-surfaces.md` — Frontend surface audit (mobile scope, active)

### Verdict

Fragmentation is **moderate but manageable**. The `issues-archive/` pattern is consistent and archival by design across all modules. Two genuinely open issues exist in module `issues/` directories. The `docs/unified-dev-pipeline/*/generated-issues/` set (20 files) is CDD-generated planning documentation, not an operational tracker — no action needed. The `tasks/11 june/` directory contains recent planning docs.

**Recommended deprecations**: None immediately — the pattern is consistent. The `Neurosense/issues-next/` queue (4 files) is the only non-standard format; consider moving to standard `issues/` or archive when done.

---

## 4. Target Readiness & Module Status

### Backend Module Summary

| Module | Backend Routes | Stubs/501s | Tests | Docker | CI | Backend % |
|--------|---------------|------------|-------|--------|----|-----------|
| **neurocnl** | 17 routers (parse, validate, generate, simulate, export, deploy, jobs, training, notebook, nir_inspect, datasets, neurosim_handoff, templates, prosthetic×3) | Notebook TODO comments (content placeholders, not 501s) | 41 backend + 22 lib = 63 files | Yes (`backend/Dockerfile`) | Yes (ci.yml, 3-OS matrix) | **~90%** |
| **Neurosim** | 8 routers (generation, export, projects, preview, components, validation, templates, sweep, spinnaker2, simulation_ws, nir_canvas) | `nir_support.py:387` raises `NotImplementedError` unconditionally on a called path | 30 test files | Yes (`Neurosim/Dockerfile`) | Yes (ci.yml) | **~82%** |
| **Neurochip** | 14 routers (targets, analysis, quantization, faults, estimation, export, deployments, akida, lava, pynq, serial, speck, spinnaker2, akida.py via proxy) | `export.py` lines 105, 138, 268 return HTTP 501 for BrainScaleS/Lava-hw/SpiNNaker; all three generator services are `raise NotImplementedError` stubs | 49 test files | Yes (`Neurochip/Dockerfile`) | Yes (ci.yml, 3-OS matrix) | **~72%** |
| **Neurobench** | 10 routers (baselines, benchmarks, comparison, faults, perturbation, regression, reports, results, runner proxy, synsense optional, pynq proxy, spinnaker2 optional) | None found | 29 test files | Yes (`Neurobench/Dockerfile`) | Yes (ci.yml, regression_ci.yml) | **~90%** |
| **Neurosense** | 9 routers (presets, encoding, recording, sessions, export, nir, quality, + hw-proxied: devices, stream, prophesee, pynq) | None found | 24 test files | Yes (`Neurosense/Dockerfile`, `Dockerfile.frontend`) | Yes (ci.yml) | **~88%** |
| **Neurohub** | 12 routers (auth, projects, assets, health, config, sharing, registry_auth, registry_artefacts, registry_search, registry_community, registry_health) | `registry_artefacts.py:65` has `pass` in exception handler (silently swallows errors) | 24 test files + 4 property test modules | Yes (`Neurohub/Dockerfile`, `frontend/Dockerfile`) | Yes (neurohub-ci.yml) | **~88%** |
| **Neuro-Dream-Hand** | No HTTP backend — library/hardware only | `pynq_emg_source.py:73` raises `NotImplementedError` for unsupported EMG hardware | 45 test files | Yes (`Neuro-Dream-Hand/Dockerfile`) | Yes (ci.yml, docker.yml, integration.yml) | **~80%** |
| **lava_backend** | Isolated Lava simulator runtime (port 8012) | None in audit scope | Not separately tested | `Dockerfile.lava` (root) | Via root CI | **~85%** |
| **jupyter worker** | Pass-through proxy for Jupyter Server + env-manager extension | None | Via root tests | `workers/jupyter_server/Dockerfile` | Via root CI | **~90%** |
| **suite_api** | Unified proxy — wires all 7 domain routers | None | Root `tests/` (34 files) | `suite_api/Dockerfile` | Root ci.yml | **~92%** |
| **nmtk launcher_control** | `server.py` (7,007 lines), deployment_executors, provisioning_helpers | `deployment_executors.py:38` has `raise NotImplementedError` (base class abstract method — expected) | Tests in root `tests/test_launcher_control_service.py` | `Dockerfile.control` | Root ci.yml | **~88%** |

### Frontend Module Summary (informational — mobile work in progress)

| Module | Frontend Dart Files | Status |
|--------|---------------------|--------|
| neurocnl | Active (large codebase) | In progress — mobile redesign |
| Neurochip | **0 Dart files** — only `neurochip.iml` | No frontend implementation |
| Neurobench | 42 Dart files in `lib/` | Present |
| Neurosense | 34 Dart files in `lib/` | Present |
| Neurohub | 40 Dart files in `lib/` | Present |

### Stubs Requiring Immediate Attention (P0/P1)

1. **`Neurochip/neurochip/app/services/brainscales_generator.py`** — entire function body is `raise NotImplementedError`. HTTP 501 returned from `/api/neurochip/export/brainscales`.
2. **`Neurochip/neurochip/app/services/lava_generator.py`** — entire function body is `raise NotImplementedError`. HTTP 501 returned from `/api/neurochip/export/lava`.
3. **`Neurochip/neurochip/app/services/spinnaker_generator.py`** — entire function body is `raise NotImplementedError`. HTTP 501 returned from `/api/neurochip/export/spinnaker`.
4. **`Neurosim/neurosim/app/services/nir_support.py:387`** — `raise NotImplementedError` on an active code path (also duplicated in `neurocnl/neurosim/`).
5. **`neurocnl/backend/app/scratch.py`** — contains a raw `print(type(job), job)` debug line. File is not a test — it is unclear if it is deployed or dead. Should be deleted or moved.
6. **`scripts/jules_batch_prompt.py:34`** — SyntaxError prevents ruff from parsing this file.

### Docker Compose (Root)

Root `docker-compose.yml` defines **15 services**:
- `suite_api` (port 9000) — main backend, healthcheck defined
- `neurosense-hw-worker` (port 8004)
- `neurobench-runner-worker` (port 8003)
- `neurochip-hw-worker` (port 8002)
- `lava-backend` (port 8012)
- `launcher-control` (port 8091)
- `neurocnl-physics-worker` (port 8006)
- `prometheus` (9090), `loki` (3100), `promtail`, `grafana` (3000), `alertmanager` (9093)
- `jupyter-server` (port 8008)

All services have healthchecks defined. `suite_api` depends on `lava-backend:healthy`. Full observability stack (Prometheus + Loki + Grafana + Alertmanager) is included.

### Root CI (.github/workflows/ci.yml)

Comprehensive: change-detection job feeds 14+ per-module jobs, each with 3-OS matrix (macOS ARM64, Windows x64, Linux x64). Stages include ruff lint, ruff format check, pytest. Additional workflows: golden-path.yml, contract-verification.yml, integration-test.yml, health-check.yml, release-docker.yml, release-desktop.yml, scheduled-status-audit.yml, nmtk-ci.yml (35 workflow files total).

**CI gap**: No workflow at root level runs `mypy` — type checking is delegated to per-module configs. Root `pyproject.toml` has no `[tool.mypy]` section.

---

## 5. Priority Work Roadmap

### P0 (Critical — Blockers)

1. **Fix SyntaxError in `scripts/jules_batch_prompt.py`** — currently breaks ruff analysis of the entire file. Either fix line 34 or add to ruff's `exclude` list.

2. **Neurochip hardware export stubs** — three export generators (`brainscales_generator.py`, `lava_generator.py`, `spinnaker_generator.py`) all raise `NotImplementedError`, causing HTTP 501 on `/api/neurochip/export/{brainscales,lava,spinnaker}`. These are the only routes that produce 501 errors in actively used paths. Must be implemented or clearly documented as out-of-scope for the POC with HTTP 501 + meaningful error message (current messages are already good).

3. **Neurochip frontend** — `Neurochip/frontend/` contains only `neurochip.iml` (IntelliJ project file). Zero Flutter/Dart implementation. NeuroChip has no user-facing UI. This has been flagged in every audit since Apr-2026.

4. **F811 test duplicates in `tests/test_launcher_control_service.py`** — functions `test_akida_host_round_trip_updates_settings_file` and `test_doctor_report_includes_akida_hosts` are each defined twice. The second definition silently shadows the first. One test case is not executing.

### P1 (Core Integration)

5. **Ruff regression: 557 → target <400** — net +154 errors since 11-Jun. Run `ruff check --fix .` to eliminate 219 auto-fixable violations. The remaining 338 require manual fixes:
   - 102 ANN101 (add `self` type hints or exclude rule)
   - 38 PGH003 (replace blanket `# type: ignore` with specific codes)
   - 30 E402 (move imports to top or add `noqa`)
   - 4 F821 (add missing `Any` import — `from typing import Any`)

6. **`Neurosim/neurosim/app/services/nir_support.py:387`** — `raise NotImplementedError` on a path that is called during active use. Determine whether this path is actually reached in production or is dead code; either implement or gate it behind a feature flag.

7. **`neurocnl/backend/app/scratch.py`** — raw debug print file in the backend package. Delete it or move to a scripts/debug/ directory excluded from the package.

8. **Neurohub `registry_artefacts.py:65` silent `pass`** — exception in artefact lookup is swallowed silently. Should log at minimum `logger.warning(...)` before passing.

### P2 (Polish/Quality)

9. **Add root-level mypy configuration** — `pyproject.toml` has no `[tool.mypy]` section. Root CI has no mypy job. Consider adding strict mypy for `suite_api/` and `nmtk/launcher_control/` at minimum (both are production critical paths).

10. **Property-based test (PBT) coverage** — Neurohub has 4 PBT modules (`tests/properties/`). Neurobench has a `properties/` folder. Other modules have none. Extend PBT to neurocnl core grammar invariants and Neurosense encoding invariants per the CDD-generated issues in `docs/unified-dev-pipeline/`.

11. **`Neurosense/issues-next/` cleanup** — 4 files in non-standard location. Migrate to `Neurosense/issues/` or archive when completed.

12. **Print-to-logging conversion in `scripts/akida_nir_demo.py`** — demo script uses 6 raw `print()` calls. Low priority but inconsistent with logging policy.

13. **`notebooks/` TODO comments in `neurocnl/backend/app/routers/notebook.py`** — 8+ inline `# TODO:` comments in generated notebook template code (e.g., `# TODO: map NIR graph to Lava processes`). These are inside notebook cell strings and are intentional user guidance, not production TODOs. They should be re-labelled `# NOTE:` to avoid confusing automated scanners.

---

*This audit is based on static analysis of the working tree on branch `dev` as of 2026-06-14. No services were started; no tests were executed. Backend readiness % estimates are based on route count, stub presence, and test file count — not pass/fail rates.*
