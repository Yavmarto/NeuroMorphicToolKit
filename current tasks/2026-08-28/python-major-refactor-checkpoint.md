# Python Major Refactor Checkpoint — 2026-08-28

## Progress

The behavior-preserving Python refactor is approximately **52% complete**, weighted by remaining
complexity. This checkpoint completes the PYNQ status-serialization slice and closes the planned
PYNQ launcher decomposition work before the program moves to NeuroCNL notebook generation.

## Completed in this slice

- Added `nmtk/launcher_control/pynq_status.py` as the pure typed owner of secret-free board wire
  serialization, preflight-to-persistence mapping, and runtime-status snapshot mapping.
- Rewired the PYNQ repository and provisioning coordinator to use that boundary while preserving
  every persisted key, response key, status value, runtime URL rule, and password-redaction rule.
- Kept `_serialize_pynq_board`, `_default_runtime_api_url`, and `_effective_runtime_api_url` as
  temporary compatibility exports through `hardware_models.py` and `server.py`.
- Narrowed the preflight evaluator's board state to the existing closed `PynqBoardState` contract.
- Added golden field/casing tests for serialization, preflight state, runtime status, credentials,
  manifest-defined runtime ports, and the complete `fetch_pynq_board_status` response.
- Updated the launcher fixture to patch the status module's manifest path, matching the new owner.

## Verification

- Focused PYNQ, persistence, packaging, and compatibility tests: **138 passed**.
- Complete launcher-control suite: **344 passed**.
- Ruff check and formatting: **passed** for all changed Python and tests.
- Strict mypy for the new status boundary and preflight evaluator: **passed**.
- Python compilation and `git diff --check`: **passed**.
- Launcher doctor: **0 fatal findings**, with **1 degraded optional capability** for unavailable
  Studio SDK extras.
- Deployment asset synchronization: **passed**.

The canonical launcher guardrail's Python and deployment-asset stages passed. Its Flutter stage
failed because concurrent NeuroCNL frontend changes declare extracted files as `part` files without
matching `part of` declarations and currently leave `_SplitNavDir`, `_kStepNames`,
`PipelineStageArea`, and `StudioStepDrawer` unresolved. Those files are outside this Python slice
and were not modified here.

## Next safe slice

Begin the NeuroCNL notebook-generation split with characterization and a transport-only router
boundary. First isolate schemas and artifact discovery behind compatibility re-exports, preserve
all endpoint and generated-notebook output, and verify golden notebook and Suite API contracts
before extracting target emitters or DAG lowering.

No data migration is required. Applying the Python launcher changes to the development host uses
the existing developer update workflow and restarts launcher-control; released users continue to
receive backend updates through Backend Setup in the app.
