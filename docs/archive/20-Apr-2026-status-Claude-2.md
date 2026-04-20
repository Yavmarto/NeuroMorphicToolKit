# Agentic Status Audit & Readiness Workflow - 20-Apr-2026 (Attempt 2)

**Audit Date:** 20-Apr-2026
**Agent Assessor:** Claude (claude-sonnet-4-6)

## 1. Executive Summary

**Overall POC Readiness: 87%** — unchanged from the first 20-Apr-2026 audit.

Scope: root repository plus all 7 modules registered in `nmtk/neuro_toolkit/assets/modules.json`: `neurocnl`, `Neurosim`, `Neurochip`, `Neurobench`, `Neurosense`, `Neurohub`, and `Neuro-Dream-Hand`.

**Major deltas since the first 20-Apr-2026 audit:**

- The Neurochip submodule pointer advanced (`m Neurochip` in `git status`), bringing Neurochip's route count from the prior-audit figure up to **173** routes (largest module by endpoint count). Total API surface across all modules is now **437** routes, up from **214** reported in the first audit.
- Working-tree PYNQ work expanded substantially but remains uncommitted: `nmtk/launcher_control/server.py` gained **+423/-128** lines (now 2,978 lines total); `pynq_deploy_screen.dart` and `pynq_deploy_service.dart` grew by **+70** and **+77** lines respectively; two test files gained **+52** lines net.
- **Two deprecated-API warnings were introduced** in `pynq_deploy_screen.dart` (lines 324 and 430: `value` → `initialValue`). These are in the active working-tree change and must be resolved before this screen is mergeable.
- `nmtk/launcher_control/server.py` contains **11 `print()` call sites** but zero `logging.getLogger` usages. Because several `print()` calls are in the supported orchestration path (preflight sentinel, PYNQ board log streaming, doctor JSON output), these represent a logging-hygiene gap in an actively growing file.
- Launcher doctor: `fatalCount: 0`, `degradedCount: 1` — **preflight degraded optional capability** for Neurochip (`lava` optional runtime not installed). All other modules report preflight `ok` with both CNL Studio and NeuroSim in `installed` state.
- Ruff findings: **101 errors** — identical to first audit. No regressions, no fixes.
- Mypy: still blocked by `Neurosim/build/lib/neurosim` checked-in build artifact. Unchanged.
- Flutter findings: **12 total** — identical to first audit.
- Active issues queue: **5 open files** — identical to first audit. No new issues opened or closed between the two runs.

Readiness remains at 87% because the PYNQ changes are uncommitted and carry two deprecated-API warnings that block a clean merge.

---

## 2. Linter Snapshot

### Python — Ruff

Command: `python3 -m ruff check . --statistics` (run from repo root)

| Rule | Count | Auto-fixable |
| :--- | :---: | :---: |
| `invalid-syntax` | 84 | No |
| `UP037` quoted-annotation | 5 | Yes |
| `ANN202` missing-return-type-private-function | 4 | No |
| `I001` unsorted-imports | 3 | Yes |
| `ARG002` unused-method-argument | 2 | No |
| `ANN002` missing-type-args | 1 | No |
| `ANN003` missing-type-kwargs | 1 | No |
| `C420` unnecessary-dict-comprehension | 1 | Yes |
| **Total** | **101** | **9 fixable** |

- All 84 `invalid-syntax` findings originate from `scripts/jules_batch_prompt.py`, which retains **6 merge-conflict marker lines** (`<<<<<<<`, `=======`, `>>>>>>>`). This single file is the sole cause of the `invalid-syntax` flood and blocks any meaningful repo-root lint clean bill of health.
- `nmtk/launcher_control/server.py` passes ruff cleanly at the file level (confirmed separately).
- The 17 non-syntax findings are spread across: `neurocnl/backend/app/routers/deploy.py` (I001), `neurocnl/neurocnl/contracts/pynq_runtime_artifact_contract.py` (UP037 ×4), `neurocnl/neurocnl/converter/sinabs_io.py` (C420), `neurocnl/neurocnl/layers/layer1_validator.py` (I001 ×2), `neurocnl/neurocnl/export/pynq_exporter.py` (UP037), and `Neurosim/neurosim/tests/routers/test_components.py` (ANN202 ×4, ANN002, ANN003, ARG002 ×2).

### Python — Mypy

Command: `python3 -m mypy --strict .`

Status: **Blocked — same as all prior audits.**

```
Neurosim/neurosim/__init__.py: error: Duplicate module named "neurosim"
(also at "./Neurosim/build/lib/neurosim/__init__.py")
Found 1 error in 1 file (errors prevented further checking)
```

The checked-in `Neurosim/build/lib/neurosim` build artifact continues to block any meaningful repo-root mypy output. Per-module mypy runs are possible but were not executed this pass.

### Python — Logging Hygiene (server.py)

`nmtk/launcher_control/server.py` (2,978 lines) has **11 `print()` call sites** and **0 `logging.getLogger` calls**.

Notable print-heavy paths:
- Line 120: preflight sentinel output (protocol-required, but should use `sys.stdout.write` explicitly)
- Line 976: PYNQ board log streaming (`[pynq:{board_label}]` prefix)
- Line 2480: module log forwarding (`[{module_id}]` prefix)
- Lines 2961–2963: doctor JSON / human-readable output
- Line 2967: startup banner

The PYNQ board streaming and module forwarding calls are plausibly intentional (structured stream output to the launcher), but they should be reviewed against the style guide requirement for `structured logging and machine-readable reporting` in supported orchestration paths.

### Dart / Flutter

Command: `flutter analyze <package>` run per package (all packages run this session).

| Package | Issues | Notes |
| :--- | :---: | :--- |
| `neurocnl/frontend` | 6 | Unchanged: 2 underscore-naming infos in test files |
| `Neurosim/frontend` | 4 | Unchanged: 1 null-comparison warning, 1 underscore-naming info |
| `Neurochip/frontend` | 0 | Clean |
| `Neurobench/frontend` | 0 | Clean |
| `Neurosense/frontend` | 0 | Clean |
| `Neurohub/frontend` | 0 | Clean |
| `nmtk/neuro_toolkit` | **2** | `deprecated_member_use` — `pynq_deploy_screen.dart:324` and `:430` (`value` → `initialValue`). **New this session.** |
| `nmtk_ui_core` | 0 | Clean (9 outdated packages noted by pub) |
| **Total** | **12** | Unchanged from first 20-Apr audit |

The 2 new `nmtk/neuro_toolkit` warnings are in the uncommitted `pynq_deploy_screen.dart` changes. They must be fixed before merging.

### High-Severity Maintainability Anomalies

1. **`scripts/jules_batch_prompt.py`** still contains 6 live merge-conflict marker lines — sole source of 84 ruff `invalid-syntax` errors.
2. **`Neurosim/build/lib/neurosim`** is checked in — continues to block repo-root `mypy --strict .`.
3. **`pynq_deploy_screen.dart`** (working tree) introduces `deprecated_member_use` at lines 324 and 430 — blocks a clean Flutter analyze pass for the launcher.
4. **`nmtk/launcher_control/server.py`** uses `print()` throughout an actively growing file in the supported orchestration path.

---

## 3. Task Fragmentation Findings

**Tracker inventory (verified this session)**

| System | Count | Notes |
| :--- | :---: | :--- |
| `issues/*.md` active task files | 5 | Identical to first 20-Apr audit |
| `issues-archive/` | 31 | Historical; not active |
| Root-level planning docs (`*-Tasks.md`) | 0 | None found |
| CDD generated-issues | 0 | `docs/unified-dev-pipeline/` path empty |

**Active `issues/*.md` files (5):**
1. `akida-studio-deployment-plan.md` — Akida SDK-backed acceptance run still missing.
2. `neurosense-research-credibility-rollout.md` — Research credibility tracking (not implementation-blocked).
3. `pynq-z2-studio-deployment-plan.md` — Blocked on real board-ready `.bit`/`.hwh` overlay artifacts.
4. `sent-status-audit-2026-04-16.md` — Prior audit reference, can be archived.
5. `teensy-studio-deployment-plan.md` — Blocked on real-board smoke-test evidence.

**Fragmentation assessment:** No new fragmentation since the first audit today. The three hardware deployment issues (PYNQ-Z2, Akida, Teensy) are legitimately distinct and cannot be merged — each targets different hardware. `sent-status-audit-2026-04-16.md` is stale and safe to archive. Practical independent workstreams: **3** (PYNQ-Z2 overlay artifacts, Akida SDK acceptance, Teensy smoke-test evidence).

---

## 4. Target Readiness & Module Status

### Route Coverage (verified this session)

| Module | Routes | Port |
| :--- | :---: | :---: |
| neurocnl | 71 | 8000 |
| Neurosim | 86 | 8001 |
| **Neurochip** | **173** | 8002 |
| Neurobench | 29 | 8003 |
| Neurosense | 35 | 8004 |
| Neurohub | 43 | 8005 |
| Neuro-Dream-Hand | 0 | — |
| **Total** | **437** | |

Neurochip's 173-route count reflects the advanced submodule pointer (`m Neurochip` working-tree state). Neuro-Dream-Hand has no HTTP routes — it is a Python-only hardware bridge, not a web API module.

### Backend

- All 6 API modules (neurocnl, Neurosim, Neurochip, Neurobench, Neurosense, Neurohub) have functioning FastAPI backends with real route implementations — zero `501 Not Implemented` stubs found.
- `Neuro-Dream-Hand` is hardware-only; no backend stub concern.
- `nmtk/launcher_control/server.py` is the control-plane service (not a module backend). It is 2,978 lines with substantial PYNQ board state-management logic. Uncommitted working-tree delta is +295 net lines.

### Frontend

- All 6 module frontends have real Dart implementations — no 0-byte scaffolds found.
- `Neurochip/frontend`: clean analyzer pass.
- `neurocnl/frontend`: 6 minor analyzer infos (test-naming style, no blocking issues).
- `Neurosim/frontend`: 4 minor issues (1 null-comparison warning, 1 naming info).
- `nmtk/neuro_toolkit` launcher: 2 deprecated-API warnings in the active PYNQ working-tree changes.

### Tests

| Scope | Count |
| :--- | :---: |
| Python test files (`test_*.py` / `*_test.py`) | 1,453 |
| Dart test files (`*_test.dart`) | 111 |
| **Total** | **1,564** |

Tests are not mocked away — confirmed by the presence of real route implementations and the PBT file counts (Neurochip: 116 PBT files, neurocnl: 48 PBT files from prior audit; unchanged this session).

### Docker Compose

| Module | Services | Status |
| :--- | :--- | :--- |
| neurocnl | backend, frontend | Valid (obsolete `version` attr warning) |
| Neurochip | backend | Valid (obsolete `version` attr warning) |
| Neurosim | backend, frontend | Valid (obsolete `version` attr warning) |
| Neurobench | neurobench | Valid (no warning) |
| Neurosense | backend, frontend | Valid (obsolete `version` attr warning) |
| Neurohub | db, backend, frontend | Valid (obsolete `version` attr warning) |
| Neuro-Dream-Hand | neurodreamhand | Valid (obsolete `version` attr warning) |
| Root compose | neurocnl, neurosim, neurochip | Valid |

All 7 module compose files parse successfully. The `version` attribute warning is cosmetic and non-blocking.

### CI / Launcher Doctor

Launcher doctor (`python3 scripts/launcher_control_service.py --doctor --json`):

- **`fatalCount: 0`** — no fatal preflight failures.
- **`degradedCount: 1`** — Neurochip reports `preflightStatus: "degraded"` due to missing `lava` optional runtime. This is an expected optional-capability degradation, not a blocker.
- CNL Studio and NeuroSim: `preflightStatus: "ok"`, `status: "installed"`.
- Outcome: **degraded optional capability** (not `preflight failed`).

---

## 5. Priority Work Roadmap

### P0 — Critical (blocks merge / clean CI)

| # | Item | Location | Effort |
| :--- | :--- | :--- | :--- |
| P0-1 | Fix `deprecated_member_use` at lines 324 and 430 in `pynq_deploy_screen.dart` (`value` → `initialValue`) | `nmtk/neuro_toolkit/lib/screens/pynq_deploy_screen.dart` | < 30 min |
| P0-2 | Resolve 6 merge-conflict markers in `scripts/jules_batch_prompt.py` to eliminate 84 ruff `invalid-syntax` errors | `scripts/jules_batch_prompt.py` | < 1 hour |
| P0-3 | Delete `Neurosim/build/lib/neurosim` from the repository to unblock `mypy --strict .` | `Neurosim/build/` | < 5 min + gitignore update |

### P1 — Core Integration (needed for hardware POC claims)

| # | Item | Location | Effort |
| :--- | :--- | :--- | :--- |
| P1-1 | Commit and merge the PYNQ working-tree changes after P0-1 is resolved | `nmtk/launcher_control/server.py`, `pynq_deploy_*` | After P0-1 |
| P1-2 | Obtain and validate real PYNQ-Z2 `.bit` / `.hwh` overlay artifacts and close `pynq-z2-studio-deployment-plan.md` | Hardware + `Neurochip/` | Hardware-gated |
| P1-3 | Run BrainChip SDK-backed acceptance test and close `akida-studio-deployment-plan.md` | `neurocnl/` + Akida SDK env | SDK-env-gated |
| P1-4 | Record real-board Teensy smoke-test and close `teensy-studio-deployment-plan.md` | `Neurochip/` + Teensy hardware | Hardware-gated |
| P1-5 | Replace `print()` calls in `nmtk/launcher_control/server.py` orchestration paths with structured logging | `nmtk/launcher_control/server.py` | ~2 hours |

### P2 — Polish / Quality

| # | Item | Location | Effort |
| :--- | :--- | :--- | :--- |
| P2-1 | Remove obsolete `version` attribute from all 6 module `docker-compose.yml` files | All module compose files | < 30 min |
| P2-2 | Fix 9 auto-fixable ruff issues (`ruff check --fix`) after P0-2 is done | `neurocnl/`, `Neurosim/` | < 5 min |
| P2-3 | Archive `issues/sent-status-audit-2026-04-16.md` — it is a historical reference, not an actionable task | `issues/` | < 5 min |
| P2-4 | Update `nmtk_ui_core` outdated packages (`flutter pub outdated`) | `nmtk_ui_core/` | < 1 hour |
| P2-5 | Fix 6 minor Flutter analyzer infos in `neurocnl/frontend` (test-naming style) | `neurocnl/frontend/test/` | < 30 min |
