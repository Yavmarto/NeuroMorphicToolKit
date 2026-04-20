# Agentic Status Audit & Readiness Workflow - 20-Apr-2026

**Audit Date:** 20-Apr-2026
**Agent Assessor:** Gemini

## 1. Executive Summary

**Overall POC Readiness: 87%** (consistent with Claude's audit from earlier today)

Scope: Root repository plus all 7 modules registered in `nmtk/neuro_toolkit/assets/modules.json`: `neurocnl`, `Neurosim`, `Neurochip`, `Neurobench`, `Neurosense`, `Neurohub`, and `Neuro-Dream-Hand`.

**Major Findings & Deltas:**
- **Code Health Improvement**: Ruff findings dropped from 148 (16-Apr) to **101** today. The primary blocker remains `scripts/jules_batch_prompt.py`, which contains 18 merge conflict markers and 84 syntax errors.
- **Type Checking Blocked**: `mypy --strict .` is still blocked by a duplicate module error caused by the checked-in `Neurosim/build/lib/neurosim` artifact.
- **Task Surface Correction**: While a previous audit today claimed the CDD-generated issue queue was gone, this audit confirms that **21 generated issues** are still active in `docs/unified-dev-pipeline/`.
- **Implementation Depth**: Substantial growth in Property-Based Testing (PBT) files was verified, with **116** files in `Neurochip` and **48** in `neurocnl` now utilizing `hypothesis`.
- **Branch State**: The branch is technically merge-clean but contains uncommitted changes in `nmtk/launcher_control/server.py` and several Flutter screen/service files related to PYNQ deployment.

## 2. Linter Snapshot

### Python
- `ruff check . --statistics`: **101 findings** total.
- Breakdown:
  - `invalid-syntax`: 84 (all within `scripts/jules_batch_prompt.py`)
  - `UP037` quoted annotations: 5
  - `ANN202` missing return type: 4
  - `I001` unsorted imports: 3
  - Others (ARG002, ANN002, ANN003, C420): 5

### Mypy
- **Result**: Blocked/Immediate Failure.
- **Blocking error**: `Neurosim/neurosim/__init__.py: error: Duplicate module named "neurosim" (also at "./Neurosim/build/lib/neurosim/__init__.py")`.
- **Note**: Build artifacts must be purged from the repository to enable full-repo type checking.

### Flutter
- `flutter analyze` across 8 packages:
  - `nmtk_ui_core`: Clean.
  - `neurocnl/frontend`: 6 issues.
  - `Neurosim/frontend`: 4 issues.
  - `nmtk/neuro_toolkit`: 2 issues.
  - Other 4 packages: Clean.
- Total findings: **12**.

## 3. Task Fragmentation Findings

**Observed tracker inventory:**
- `issues/*.md`: 5 active tasks (down from 21 on 16-Apr).
- `docs/unified-dev-pipeline/*/generated-issues/*.md`: **21 active issues** (verified present, contrary to earlier report today).
- `issues-archive/`: Historical records only.

**Consolidated remaining task count:**
- Practical independent workstreams: **~26** (5 curated + 21 generated).
- Major focus area: Cross-module hardware integration (Teensy, PYNQ, Akida).

## 4. Target Readiness & Module Status

| Module | Readiness | Backend | Frontend | Tests | Contracts | Docker | CI |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- | :--- |
| **Root Infrastructure** | **75%** | `server.py` is functional but has uncommitted changes | `nmtk_ui_core` is clean | Root tests exist | `modules.json` is healthy | Root compose parses | 34 workflows |
| **neurocnl** | **87%** | 23+ routes, no 501 stubs | 0 empty scaffolds, 6 analyzer issues | 48 PBT files (verified) | 26 contracts | Parses | 8 workflows |
| **Neurosim** | **87%** | 20+ routes, no 501 stubs | 0 empty scaffolds, 4 analyzer issues | Py tests present | 15 contracts | Parses | 8 workflows |
| **Neurochip** | **87%** | 43 routes, 1 fallback stub | 0 empty scaffolds, clean | 116 PBT files (verified) | 13 contracts | Parses | 8 workflows |
| **Neurobench** | **87%** | 27 routes, 1 fallback stub | 0 empty scaffolds, clean | Py + Dart tests | 6 contracts | Parses | 10 workflows |
| **Neurosense** | **100%** | 28+ routes, clean | 0 empty scaffolds, clean | Py + Dart tests | 7 contracts | Parses | 8 workflows |
| **Neurohub** | **100%** | 33+ routes, clean | 0 empty scaffolds, clean | Py + Dart tests | 6 contracts | Parses | 8 workflows |
| **Neuro-Dream-Hand** | **90%** | CLI-only, implementation real | N/A | Py tests present | 5 contracts | Parses | 11 workflows |

## 5. Priority Work Roadmap

### P0 (Critical)
- **Resolve `scripts/jules_batch_prompt.py`**: Fix 18 merge conflict markers and 84 syntax errors to unblock Ruff.
- **Purge Build Artifacts**: Remove `Neurosim/build/` to unblock `mypy --strict .`.
- **Commit/Verify PYNQ work**: Finish and commit the pending changes in `nmtk/launcher_control/server.py` and associated Flutter files.

### P1 (Core Integration)
- **Address Flutter analyzer issues**: Fix the 12 issues across `neurocnl`, `Neurosim`, and `nmtk`.
- **CDD Issue Triage**: Execute the 21 generated issues in `docs/unified-dev-pipeline/` to finalize module contract coverage.
- **Hardware Proofs**: Consolidate Teensy/PYNQ/Akida deployment evidence as per `issues/` plans.

### P2 (Polish/Quality)
- **Log Refinement**: Transition remaining `print()` calls in backend services to structured logging.
- **Contract Expansion**: Broaden modeling in `Neuro-Dream-Hand` and `Neurobench`.
