# Agentic Status Audit & Readiness Workflow - 16-Apr-2026

**Audit Date:** 16-Apr-2026
**Agent Assessor:** Antigravity

## 1. Executive Summary
**Overall POC Readiness: 85%**

This audit was executed from the repository root (`/Users/yoshimartodihardjo/NeuroMorphicToolKit/scripts` inside the root checkout), so the scope covers root infrastructure plus all 7 modules registered in `nmtk/neuro_toolkit/assets/modules.json`: `neurocnl`, `Neurosim`, `Neurochip`, `Neurobench`, `Neurosense`, `Neurohub`, and `Neuro-Dream-Hand`.

Implementation reality is materially stronger than the current branch hygiene suggests. Across the audited modules there are `312` Python test files, `84` Dart test files, `26` property-test files, `41` contract files, `318` non-empty Dart files, `0` empty Dart scaffolds, `7/7` module compose files that parse with `docker compose config --services`, and module-local CI workflow directories for every mapped module.

The main gap between CI optics and branch reality is now concentrated in root/tooling health:
- `ruff check . --statistics` found `148` findings, with `126` `invalid-syntax` errors concentrated in `scripts/jules_batch_prompt.py`.
- `mypy --strict .` aborted immediately on `Neurosim/neurosim/__init__.py` because `Neurosim/build/lib/neurosim/__init__.py` creates a duplicate package root.
- `git status --short` shows the branch is already dirty and in a merge-conflict state (`UU scripts/jules_batch_prompt.py`), which materially affects audit outcomes and commitability.

Readiness percentages in Section 4 use a simple evidence rubric: each audited surface (`Backend`, `Frontend`, `Tests`, `Contracts`, `Docker`, `CI`) scores `1.0` when directly verified and clean, `0.5` when implemented but materially limited, and `0.0` when missing. Percentages are the arithmetic average across applicable surfaces.

**Major deltas since the last root audit on 11-Apr-2026:**
- Root static-analysis health regressed on the current branch: `ruff check .` moved from `7` findings to `148`, driven mostly by merge-conflict markers in `scripts/jules_batch_prompt.py`.
- Root `mypy --strict .` is now blocked before broader checking begins because checked-in `Neurosim/build/lib/neurosim` duplicates the live package root.
- Flutter is no longer clean across all packages: `neurocnl/frontend` has `6` analyzer findings, `Neurosim/frontend` has `4`, and `nmtk/neuro_toolkit` has `2`; the other `5` packages analyzed cleanly.
- Task fragmentation is lower than the 11-Apr report implied once archive noise is removed: there are `42` task-like active artifacts (`21` `issues/*.md` tasks plus `21` generated CDD issues), not a 70+ live queue.
- Implementation depth remains high despite those regressions: no empty Dart scaffolds were found in audited modules, every mapped module still has tests, Docker, and CI surfaces, and live backend `501` paths are limited to optional-runtime fallbacks in `Neurochip` and `Neurobench`.

## 2. Linter Snapshot
### Python
- `ruff check . --statistics`: `148` findings total.
- Breakdown:
  - `invalid-syntax`: `126`
  - `I001` unsorted imports: `7`
  - `UP037` quoted annotations: `5`
  - `ANN202`: `4`
  - `ARG002`: `2`
  - `ANN002`: `1`
  - `ANN003`: `1`
  - `C420`: `1`
  - `F401`: `1`
- `invalid-syntax` is not repo-wide random breakage; all `126` syntax findings come from one conflicted file: `scripts/jules_batch_prompt.py`.
- Logging style is inconsistent at repo scope: `rg` found `740` Python `print()` call sites versus `68` `logging.getLogger(...)` call sites.

### Mypy
- Command run: `mypy --strict .`
- Result: immediate failure, not a trustworthy full-repo type snapshot.
- Blocking error:

```text
Neurosim/neurosim/__init__.py: error: Duplicate module named "neurosim" (also at "./Neurosim/build/lib/neurosim/__init__.py")
Found 1 error in 1 file (errors prevented further checking)
```

- Interpretation: strict typing integrity cannot currently be audited from the repo root without excluding checked-in build artifacts or restructuring package discovery.

### Flutter
- `flutter analyze` was run in all `8` discovered Flutter packages.
- Root checkout already contained `nmtk_ui_core`, so the isolated-frontend exception was not needed.
- Package results:

| Package | Result |
| :--- | :--- |
| `neurocnl/frontend` | `6` issues |
| `Neurosim/frontend` | `4` issues |
| `Neurochip/frontend` | clean |
| `Neurobench/frontend` | clean |
| `Neurosense/frontend` | clean |
| `Neurohub/frontend` | clean |
| `nmtk/neuro_toolkit` | `2` issues |
| `nmtk_ui_core` | clean |

- Total Flutter analyzer findings observed: `12`.
- These are real code findings, not path-resolution failures.

### High-Severity Maintainability Anomalies
- `scripts/jules_batch_prompt.py` contains live merge-conflict markers and is the dominant root lint blocker.
- `Neurosim/build/lib/neurosim` is checked in and breaks repo-root strict mypy by duplicating the package namespace.
- Root Python hygiene still leans heavily on `print()` output rather than structured logging.

## 3. Task Fragmentation Findings
**Observed tracker inventory**
- `issues/*.md` task files: `21` task-like items (`23` files total minus `issues/README.md` and `issues/sent-status-audit-2026-04-16.md`)
- Generated CDD issues: `21`
- Archived issue files: `518`

**Confirmed fragmentation patterns**
1. `nmtk/issues-archive/` and `nmtk/neuro_toolkit/issues-archive/` mirror one another by filename for launcher/archive work. This is pure duplication and should not be used as active planning input.
2. Root hardware rollout issues duplicate module-owned implementation tracks:
   - `issues/teensy-studio-deployment-plan.md` overlaps `Neurochip/issues/001-teensy-real-hardware-validation.md` and `Neurochip/issues/004-fix-teensy-serial-port-backend-contract.md`.
   - `issues/pynq-z2-studio-deployment-plan.md` overlaps `Neurochip/issues/003-pynq-z2-finn-compilation.md` and `neurocnl/issues/005-pynq-finn-compilation-pipeline.md`.
   - `issues/akida-studio-deployment-plan.md` overlaps the same cross-module Akida contract/deployment surface already represented in module work.
3. Some generated issues are stale against checked-in reality:
   - `docs/unified-dev-pipeline/neurohub/generated-issues/03-neurohub-create-ci-from-scratch-and-add-cdd-pbt-verification.md` says Neurohub has no CI, but `Neurohub/.github/workflows/` currently contains `8` workflows.
4. Some active module issues overlap generated contract work rather than representing separate bodies of work:
   - `Neurochip/issues/002-contract-version-pinning.md` overlaps Neurochip generated contract extraction work.
   - `Neurosim/issues/002-bidirectional-graph-cnl-sync.md` overlaps the generated Neurosim contract/CNL-sync track.

**Consolidated remaining task count**
- Raw active task-like artifacts: `42` (`21` issues + `21` generated issues)
- Clear overlap/staleness clusters observed directly: at least `5`
- Practical independent workstreams: about `37`

**Tracking systems that should be deprecated for active planning**
- All `issues-archive/` directories
- The duplicated `nmtk/neuro_toolkit/issues-archive/` mirror
- Prompt/artifact files under `issues/` such as `issues/sent-status-audit-2026-04-16.md`
- Generated CI tickets that contradict checked-in workflow state until they are regenerated

**Recommendation**
- Keep active planning to two systems only:
  - `issues/*.md` for live human-curated integration work
  - `docs/unified-dev-pipeline/*/generated-issues/*.md` for live CDD-generated module work

## 4. Target Readiness & Module Status
**Scoring note:** percentages below are computed from direct evidence across `Backend`, `Frontend`, `Tests`, `Contracts`, `Docker`, and `CI`, with `1.0` for verified-clean, `0.5` for implemented-but-limited, and `0.0` for missing. `Neuro-Dream-Hand` omits the frontend category because `modules.json` marks it CLI-only.

| Scope | Readiness | Backend | Frontend | Tests | Contracts | Docker | CI |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- | :--- |
| **Root Infrastructure** | **75%** | Root control-plane scripts are implemented, but current branch state is blocked by merge markers in `scripts/jules_batch_prompt.py`; root `mypy --strict .` also aborts on `Neurosim/build/lib/neurosim` duplication | Shared UI is real: `nmtk_ui_core` analyzed clean, `nmtk/neuro_toolkit` has `2` deprecation findings | Root tests exist but were not executed in this audit | `modules.json` is populated and maps all `7` audited modules | Root `docker-compose.yml` parses; default services resolve to `neurochip`, `neurocnl`, `neurosim`, with additional modules behind profiles | Root `.github/workflows/` contains `34` workflows |
| **neurocnl** | **83%** | `26` detected routes, `0` live `501` files; backend is real, but root Ruff still hits backend files such as `backend/app/routers/deploy.py` and `neurocnl/layers/layer1_validator.py` | `101` Dart files, `32` widgets, `14` providers, `0` empty scaffolds; `flutter analyze` reports `6` issues | `103` Python tests, `22` Dart tests, `3` PBT files | `12` contract files | `docker-compose.yml` parses with `backend,frontend` | `8` module workflows |
| **Neurosim** | **83%** | `22` detected routes, `0` live `501` files; backend surface is real, but checked-in `build/lib/neurosim` breaks repo-root strict mypy | `54` Dart files, `9` widgets, `9` providers, `0` empty scaffolds; `flutter analyze` reports `4` issues | `33` Python tests, `10` Dart tests, `2` PBT files | `4` contract files | `docker-compose.yml` parses with `backend,frontend` | `8` module workflows |
| **Neurochip** | **83%** | `45` detected routes; one live `501` path remains in `neurochip/app/routers/akida.py` for `AkidaSdkNotAvailableError` | `39` Dart files, `13` widgets, `5` providers, frontend analyzes clean | `38` Python tests, `7` Dart tests, `5` PBT files | `8` contract files | `docker-compose.yml` parses with `backend` | `8` module workflows |
| **Neurobench** | **83%** | `28` detected routes; one live `501` fallback remains in `neurobench/app/routers/spinnaker2.py` on `ImportError` | `32` Dart files, `16` widgets, `2` providers, frontend analyzes clean | `29` Python tests, `10` Dart tests, `5` PBT files | `5` contract files | `docker-compose.yml` parses with `neurobench` | `10` module workflows |
| **Neurosense** | **100%** | `32` detected routes, `0` live `501` files observed | `37` Dart files, `16` widgets, `10` providers, frontend analyzes clean | `33` Python tests, `12` Dart tests, `4` PBT files | `6` contract files | `docker-compose.yml` parses with `backend,frontend` | `8` module workflows |
| **Neurohub** | **92%** | `34` detected routes, `0` live `501` files; SQLAlchemy/Alembic and a database compose service are wired, but schema function was not exercised in this audit | `55` Dart files, `23` widgets, `5` providers, frontend analyzes clean | `32` Python tests, `23` Dart tests, `5` PBT files | `4` contract files | `docker-compose.yml` parses with `db,backend,frontend` | `8` module workflows |
| **Neuro-Dream-Hand** | **80%** | CLI-only module with `0` HTTP routes and no `501` stubs; implementation is real, but active work still centers on HITL/deployment evidence rather than closed POC proof | N/A by manifest (`hasFrontend: false`) | `44` Python tests, `2` PBT files | `2` contract files; generated pipeline work still calls for broader contract extraction | `docker-compose.yml` parses with `neurodreamhand` | `11` module workflows |

**Cross-module proof totals**
- Routes detected across mapped modules: `187`
- Python test files: `312`
- Dart test files: `84`
- Property-test files: `26`
- Contract files: `41`
- Module Dart files: `318`
- Empty module Dart files: `0`
- Module compose files that parse: `7/7`

**Backend-specific observations**
- No broad `501 Not Implemented` scaffold pattern remains.
- The only live `501` backend surfaces found in audited module source are:
  - `Neurochip/neurochip/app/routers/akida.py`
  - `Neurobench/neurobench/app/routers/spinnaker2.py`
- Both are optional-runtime fallbacks, not empty CRUD scaffolds.

**Frontend-specific observations**
- No audited module frontend contains `0`-byte `.dart` scaffolds.
- The current frontend gaps are analyzer-level correctness/deprecation findings, not missing widget/provider bodies.

**Docker-specific observations**
- All module-level compose files parsed successfully with `docker compose -f <file> config --services`.
- Compose services observed:
  - `neurocnl`: `backend,frontend`
  - `Neurosim`: `backend,frontend`
  - `Neurochip`: `backend`
  - `Neurobench`: `neurobench`
  - `Neurosense`: `backend,frontend`
  - `Neurohub`: `db,backend,frontend`
  - `Neuro-Dream-Hand`: `neurodreamhand`

## 5. Priority Work Roadmap
### P0 (Critical)
- Resolve the merge conflict in `scripts/jules_batch_prompt.py`; it is the direct cause of `126` of the `148` current Ruff findings and keeps the working branch in an unmerged state.
- Remove or exclude checked-in build artifacts such as `Neurosim/build/lib/neurosim` from root strict-mypy discovery so `mypy --strict .` can become a meaningful repo-root signal.
- Decide whether the remaining `501` fallback behavior in `Neurochip` Akida verification and `Neurobench` SpiNNaker2 execution is the intended POC boundary or still-open functionality debt.
- Canonicalize active planning to `issues/*.md` plus `docs/unified-dev-pipeline/*/generated-issues/*.md`, and stop treating archive mirrors as live scope.

### P1 (Core Integration)
- Clean the remaining frontend analyzer issues in `neurocnl/frontend`, `Neurosim/frontend`, and `nmtk/neuro_toolkit`.
- Consolidate the duplicate hardware-proof workstreams:
  - Teensy rollout
  - PYNQ rollout
  - Akida rollout
- Refresh stale generated CI issues, starting with Neurohub, so the task system matches checked-in workflow reality.
- Reduce production-path `print()` usage in runtime services and control-plane scripts in favor of structured logging.

### P2 (Polish/Quality)
- Remove residual Ruff hygiene issues outside the merge-conflict blast radius (`I001`, `UP037`, `ANN*`, `F401`, `C420`).
- Broaden contract extraction where the generated issue queue still points to under-modeled surfaces, especially in `Neuro-Dream-Hand`.
- Re-run the root audit after the branch is merge-clean to separate permanent code health debt from temporary branch-state noise.
