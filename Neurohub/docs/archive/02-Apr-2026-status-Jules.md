# Agentic Status Audit and Readiness Report - 02-Apr-2026

**Audit Date:** 02-Apr-2026
**Agent Assessor:** Jules

## Executive Summary
**Overall POC Readiness: 85%**

NeuroMorphicToolKit (NMTK) - Neurohub module exhibits a strong foundation with functional backend routes, a rich set of frontend widgets, and a comprehensive (though currently partially failing) test suite. The core architecture is sound, but several critical "last-mile" issues in the workflow engine and CI pipeline prevent a 100% readiness score.

Major deltas since last run:
- Integrated unified authentication stack.
- Completed multi-app workflow engine (initial version).
- Established property-based testing for contracts.
- Frontend transitioned to Riverpod-based state management.

## Linter Snapshot
- **Ruff:** 11 errors found.
  - *Severe:* Undefined names (`app_name`, `endpoint`, etc.) in `neurohub/app/services/workflow_engine.py` (F821).
  - *Minor:* Unused imports (F401), missing exception chaining (B904).
- **Mypy:** Significant typing integrity issues (~100+ errors when running without plugins).
  - *Issue:* Plugin `sqlalchemy.ext.mypy.plugin` failed to load in the current environment despite SQLAlchemy being installed, causing cascading `BaseModel` and `DeclarativeBase` errors.
- **Flutter Analyze:** Blocked.
  - *Cause:* Missing local dependency `nmtk_ui_core` in the provided environment. `pub get` fails, preventing static analysis.

## Task Fragmentation Findings
- **Consolidated Task Count:** 8 active P0/P1 production-readiness issues identified in `issues-archive/`.
- **Deprecated Systems:** POC-phase tasks (001-005) in `issues-archive/` are officially superseded by the `PROD-*` series and should be formally archived or deleted to reduce noise.
- **Fragmentation:** Task tracking is currently split between `plan.md` and `issues-archive/`. `plan.md` should be transitioned to a high-level roadmap, while `issues-archive/` (or a dedicated `issues/` folder) serves as the source of truth for atomic work items.

## Target Readiness & Module Status

### Backend (90%)
- **API Routes:** 100% implemented. No 501 stubs detected.
- **Schemas:** Pydantic models fully defined for all 5 data contracts.
- **Database:** Alembic migrations are valid and reflect the current schema.
- **Stubs:** `workflow_engine.py` contains runtime-breaking undefined variables in its execution loop.

### Frontend (80%)
- **UI Widgets:** High coverage of functional widgets (`AssetCard`, `ProjectCard`, `WorkflowStepCard`).
- **Providers:** Riverpod providers implemented for Auth, Dashboard, and Activity.
- **Scaffolds:** Verified no 0-byte files; all files contain real Dart code.
- **Blockers:** Build depends on an external/sibling package `nmtk_ui_core` which is not present in the submodule scope.

### Tests (75%)
- **Unit/Integration:** 32 Python tests, 22 Dart tests.
- **PBT:** 5 property-based tests for contracts in `neurohub/tests/properties/`.
- **Status:** Several integration tests (e.g., `test_prod_integration.py`) are known to fail due to the workflow engine bugs.

### Contracts (100%)
- Fully defined in `neurohub/contracts/` for Bundles, Orchestration, Projects, and Workflows.

### Docker (95%)
- `Dockerfile` and `docker-compose.yml` are production-hardened (non-root users, healthchecks) and functional.

### CI (70%)
- Workflows exist but are hampered by environment-specific dependency issues (Flutter) and code-level bugs (Python).

## Priority Work Roadmap

### P0: Critical (Blockers)
1. **Fix `workflow_engine.py`:** Resolve undefined variable errors (`app_name`, `endpoint`, etc.) causing execution failures.
2. **Resolve Flutter Dependencies:** Address the `nmtk_ui_core` path issue in `pubspec.yaml` to enable frontend builds and analysis.
3. **Repair CI Pipeline:** Ensure `ruff` and `mypy` pass in the CI environment by fixing the identified errors.

### P1: Core Integration
1. **Functional E2E Coverage:** Complete [PROD-024] to verify the "Happy Path" across backend and frontend.
2. **Asset Integrity:** Implement SHA256 and type validation for assets [PROD-022].
3. **Workflow DAG Edge Cases:** Resolve cycle detection and isolated step issues in the workflow engine [PROD-021].

### P2: Polish/Quality
1. **Docstring Expansion:** Complete Google-style docstrings for all service modules to comply with `CODING_STYLE_GUIDE.md`.
2. **Task Consolidation:** Move active issues from `issues-archive/` to a canonical `issues/` directory and update `plan.md`.
3. **Mypy Plugin Fix:** Resolve the SQLAlchemy plugin loading issue to achieve strict typing compliance.
