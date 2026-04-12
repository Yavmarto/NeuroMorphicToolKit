# Agentic Status Audit & Readiness Workflow - 11-Apr-2026

**Audit Date:** 11-Apr-2026
**Agent Assessor:** Codex

---

## 1. Executive Summary
**Overall POC Readiness: 86%**

This audit was executed from the repository root, so it covers root infrastructure plus all 7 modules registered in `nmtk/neuro_toolkit/assets/modules.json`. The suite is materially more implementation-complete than the tracker sprawl suggests: root Docker validation passed `10/10`, all 7 module `docker compose` configs parsed successfully, all 8 discovered Flutter packages passed `flutter analyze`, and 4 modules (`Neuro-Dream-Hand`, `neurocnl`, `Neurosense`, `Neurohub`) passed `mypy --strict` cleanly.

The strongest implementation proof from this run is structural and current: `275` Python test files, `21` property-test files, `42` dedicated contract files in module contract directories, and `212` non-empty frontend Dart files were found across the audited module set. Root CI coverage is real as well: `.github/workflows/` currently contains `34` workflow files, and each audited module has its own workflow set checked in.

The main readiness drag has shifted away from missing scaffolds and toward consistency at the type and boundary layer. Root-scope Ruff debt is now small at `7` findings total, but strict typing still has two serious gaps: `Neurochip` reports `334` errors in `35` files, and `Neurobench` currently triggers a mypy internal error at `Neurobench/neurobench/app/config.py:5`, which blocks a trustworthy strict-typing result there. `Neurosim` is close behind with a single strict-mypy error and most of the remaining Ruff findings concentrated in `Neurosim/neurosim/app/services/neurocnl_bridge.py`.

**Major deltas since the prior 08-Apr-2026 root audit:**
- Root Ruff findings dropped from `437` to `7`.
- Flutter analyzer findings dropped from `17` to `0` across the same 8 packages.
- The earlier Neurosense merge-conflict blocker is gone: no Git conflict markers were found, and `Neurosense` now passes `mypy --strict` across `52` source files.
- `Neurochip` remains the largest typing risk, but the strict-mypy count is lower than the previous audit (`334` now vs `370` then).
- `Neurobench` no longer looks clean from a typing perspective because mypy currently crashes internally on `app/config.py`; that needs investigation before its backend can be treated as fully type-verified.

---

## 2. Linter Snapshot

### Python
- **Ruff:** `ruff check . --statistics` found `7` issues total.
  - `E402` module-import-not-at-top-of-file: `5`
  - `COM812` missing-trailing-comma: `1`
  - `SLF001` private-member-access: `1`
- **Where the Ruff debt lives:** `Neurosim/neurosim/app/services/neurocnl_bridge.py`, `Neurosim/neurosim/tests/services/test_neurocnl_bridge_bootstrap.py`, and `scripts/launcher_control_service.py`.
- **Logging vs. print:** direct search found `710` `print()` call sites versus `67` `logging.getLogger()` call sites.

### Mypy (`--strict`)
| Scope | Result |
| :--- | :--- |
| `Neuro-Dream-Hand` | **Pass** (`53` source files checked) |
| `neurocnl` | **Pass** (`235` source files checked) |
| `Neurosense` | **Pass** (`52` source files checked) |
| `Neurohub` | **Pass** (`89` source files checked) |
| `Neurochip` | **334 errors** in `35` files (`96` source files checked) |
| `Neurobench/neurobench` | **Mypy internal error** at `app/config.py:5` |
| `Neurosim` | **1 error** in `1` file (`45` source files checked) |

### Dart / Flutter
- **Packages analyzed:** `8`
- **Packages clean:** `Neurohub/frontend`, `Neurosim/frontend`, `nmtk_ui_core`, `Neurochip/frontend`, `nmtk/neuro_toolkit`, `Neurosense/frontend`, `neurocnl/frontend`, `Neurobench/frontend`
- **Total Flutter analyzer issues observed:** `0`
- **Isolation exception usage:** not needed in this run because `nmtk_ui_core` resolved locally and analyzed directly.

---

## 3. Task Fragmentation Findings

| System | Count | Current Value | Recommendation |
| :--- | ---: | :--- | :--- |
| Root `issues/` | `25` active markdown files | Main cross-module queue | **Retain as primary integration queue** |
| Unified `generated-issues/` | `21` active markdown files | Main module-level CDD queue | **Retain, but refresh stale items** |
| Submodule-local `issues/` | `28` active markdown files | Parallel issue systems spread across modules | **Deprecate for active planning** |
| `docs/issues - future/` | `3` markdown files | Backlog only | **Retain as future backlog** |
| `issues-archive/` | `481` archived markdown files | Historical record only | **Deprecate for active planning** |
| `*-Tasks.md` | `0` files | No live role in current tracking | **No action needed** |

**Confirmed overlap and staleness:**
1. `issues/09-opus-pynq-runtime-artifact-contract.md` overlaps work already represented by `docs/unified-dev-pipeline/neurochip/generated-issues/01-neurochip-extract-hardware-profile-deployment-and-quantization-contracts.md` and partly by `docs/unified-dev-pipeline/neurocnl/generated-issues/01-neurocnl-extract-grammar-invariant-and-export-contracts-from-the-spec-plan.md`.
2. `issues/18-opus-akida-deployment-contract.md` overlaps the same shared deployment and quantization contract surface instead of being a cleanly separate workstream.
3. `docs/unified-dev-pipeline/neurohub/generated-issues/03-neurohub-create-ci-from-scratch-and-add-cdd-pbt-verification.md` is stale as written: it says Neurohub has no CI, but `Neurohub/.github/workflows/` currently contains `8` workflow files.
4. Submodule-local issue folders still hold `28` active markdown files, which splits planning across at least three active systems for the same suite.

**Consolidated remaining task count:**
- Verified active planning files across root issues, generated issues, and submodule-local issues: `74`
- Verified duplicate or stale clusters from direct inspection: `at least 3`
- Conservative independent planning surface: **about 70 items, not 74 distinct tasks**

**Tracking systems that should be deprecated for active planning:**
- All submodule-local `issues/` folders
- All `issues-archive/` folders
- Any generated CI issue that no longer matches the checked-in workflow state until it is regenerated

---

## 4. Target Readiness & Module Status

**Cross-module implementation proof**
- Python test files: `275`
- Property-test files: `21`
- Dedicated contract files: `42`
- Frontend Dart files under `frontend/lib/`: `212`
- Empty frontend Dart scaffolds: `0`

| Scope | Readiness | Backend | Frontend | Tests | Contracts | Docker | CI | Status Notes |
| :--- | :---: | :--- | :--- | :--- | :--- | :---: | :---: | :--- |
| **Root Infrastructure** | **87%** | Root launcher/control plane is real; `.github/workflows/` has `34` workflows | `nmtk_ui_core` and `nmtk/neuro_toolkit` both analyze clean | Root integration tests are present | N/A | ✅ | ✅ | Strong infra baseline; remaining root Ruff debt includes `scripts/launcher_control_service.py` and tracker sprawl |
| **Neuro-Dream-Hand** | **90%** | Real CLI/backend package, no `501` route stubs found | N/A | `42` tests / `1` PBT | `3` contract files | ✅ | ✅ | Clean `mypy --strict`; no frontend burden |
| **neurocnl** | **92%** | `9` router/API files; no backend `501` hits found | `67` non-empty Dart files; analyzer clean | `96` tests / `3` PBT | `13` contract files | ✅ | ✅ | Strongest mixed backend/frontend module in this run; strict mypy clean |
| **Neurosim** | **87%** | `25` router/API files; no backend `501` hits found | `37` non-empty Dart files; analyzer clean | `28` tests / `2` PBT | `5` contract files | ✅ | ✅ | Near-ready, but one strict-mypy error and most remaining Ruff debt sit in `neurocnl_bridge.py` |
| **Neurochip** | **78%** | `13` router/API files; `app/routers/akida.py` still returns `501` on unsupported backend errors | `30` non-empty Dart files; analyzer clean | `33` tests / `4` PBT | `9` contract files | ✅ | ✅ | Largest current blocker: `334` strict-mypy errors in `35` files |
| **Neurobench** | **83%** | `13` router/API files; `app/routers/spinnaker2.py` can return `501` on backend exceptions | `22` non-empty Dart files; analyzer clean | `24` tests / `3` PBT | `0` dedicated contract files under `app/contracts` | ✅ | ✅ | Backend is real, but strict typing is currently blocked by a mypy internal error at `app/config.py:5` |
| **Neurosense** | **88%** | `12` router/API files; no backend `501` hits found | `24` non-empty Dart files; analyzer clean | `24` tests / `3` PBT | `7` contract files | ✅ | ✅ | Strong recovery versus the prior audit; strict mypy clean and no conflict markers found |
| **Neurohub** | **90%** | `12` router/API files; no backend `501` hits found | `32` non-empty Dart files; analyzer clean | `28` tests / `5` PBT | `5` contract files | ✅ | ✅ | One of the healthiest modules; the generated “no CI” issue is now stale |

**Docker details**
- Root validation via `./scripts/validate_docker_compose.sh`: `10 passed, 0 failed`
- Module `docker compose config --quiet`: all `7/7` module compose files passed
- Obsolete `version` key warnings remain in `neurocnl`, `Neurosim`, `Neurochip`, `Neurosense`, and `Neuro-Dream-Hand`

---

## 5. Priority Work Roadmap

### P0 (Critical)
- Fix `Neurobench/neurobench/app/config.py:5` so `mypy --strict` can run without crashing; until then, Neurobench’s type-health status is not trustworthy.
- Cut down `Neurochip` strict typing debt, starting with the high-volume untyped test/helper patterns in `neurochip/tests/test_artifact_contracts.py` and adjacent typed-call failures.
- Resolve the remaining `Neurosim` bridge issues in `Neurosim/neurosim/app/services/neurocnl_bridge.py` and the paired private-member test in `Neurosim/neurosim/tests/services/test_neurocnl_bridge_bootstrap.py`.
- Decide whether the `501` fallback behavior in `Neurochip` Akida routes and `Neurobench` SpiNNaker2 routes is the intended POC boundary or a gap that should be closed before demos.

### P1 (Core Integration)
- Canonicalize active planning on `issues/` plus `docs/unified-dev-pipeline/*/generated-issues/` only, and freeze submodule-local `issues/` folders as historical context.
- Regenerate or rewrite stale generated CI items, starting with `docs/unified-dev-pipeline/neurohub/generated-issues/03-neurohub-create-ci-from-scratch-and-add-cdd-pbt-verification.md`.
- Replace production-path `print()` usage with structured logging in runtime services first, starting with launcher control, Neurohub workflow execution, and Neurosim websocket/component loading paths.

### P2 (Polish / Quality)
- Remove obsolete `version` keys from module compose files that still emit Docker warnings.
- Clean the remaining root Ruff findings once the Neurosim bridge changes land.
- Add or formalize a dedicated contract layer for Neurobench if benchmark payload schemas are intended to be contract-checked in the same way as the other modules.

---
*End of Report*
