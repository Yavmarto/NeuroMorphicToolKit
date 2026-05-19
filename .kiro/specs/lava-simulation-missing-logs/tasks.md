# Implementation Plan

## Overview

This plan fixes the missing structured logging in `neurocnl/backend/app/routers/simulators.py` for all four Lava simulation failure modes: gateway timeout, `LavaDispatchError`, unexpected exception, and missing dependency. The workflow follows the exploratory bugfix methodology: write tests against unfixed code first to confirm the bug, then apply five surgical additions to `simulators.py`, then validate the fix and confirm no regressions.

## Task Dependency Graph

```json
{
  "waves": [
    ["1", "2"],
    ["3"],
    ["4"]
  ]
}
```

Tasks 1 and 2 are independent and run in parallel (Wave 1). Task 3 (the fix and its sub-tasks) cannot start until tasks 1 and 2 are complete (Wave 2). Task 4 runs after the fix is validated (Wave 3).

## Tasks

- [ ] 1. Write bug condition exploration test (BEFORE implementing the fix)
  - **Property 1: Bug Condition** - Lava Failure Paths Produce Zero Log Entries
  - **CRITICAL**: This test MUST FAIL on unfixed code — failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior — it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples demonstrating that each Lava failure mode emits no structured log entry
  - **Scoped PBT Approach**: For each deterministic failure mode, scope the property to the concrete failing input (missing-dep, dispatch-error, unexpected-exception, gateway-timeout structural check)
  - Create `neurocnl/backend/tests/test_simulators_logging_exploration.py`
  - Capture structlog output using `structlog.testing.capture_logs()` (a `structlog.testing.LogCapture` bound processor)
  - **Sub-case A — Missing-dependency path**: Patch `backend.app.routers.simulators._is_available` to return `False` and `backend.app.routers.simulators._lava_worker_url` to return `None`; call `POST /api/simulators/run` with `backend_name="lava_sim"` and a valid CNL spec; assert `captured_logs == []` (zero entries with `backend="lava_sim"`)
  - **Sub-case B — LavaDispatchError path**: Patch `_is_available` to return `True`; patch `neurocnl.runtime.lava_simulator.LavaSimulatorAdapter.run` to raise `LavaDispatchError("test dispatch error")`; assert `captured_logs == []`
  - **Sub-case C — Unexpected-exception path**: Patch `LavaSimulatorAdapter.run` to raise `RuntimeError("unexpected")`; assert `captured_logs == []`
  - **Sub-case D — Gateway-timeout / pre-call structural check**: Inspect the source of `neurocnl/backend/app/routers/simulators.py`; assert there is no `logger` identifier in the module (confirming the structural absence that causes the timeout blind spot)
  - Run all sub-cases on **UNFIXED** code
  - **EXPECTED OUTCOME**: All four sub-case assertions pass (zero log entries / no logger found), confirming the root cause is the absence of `import structlog` and call sites
  - Document the counterexamples found (e.g., "LavaDispatchError('test dispatch error') raised → captured_logs == []")
  - Mark task complete when the test is written, run, and all failures are documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [ ] 2. Write preservation property tests (BEFORE implementing the fix)
  - **Property 2: Preservation** - Non-Buggy Paths Return Identical Results After the Fix
  - **IMPORTANT**: Follow observation-first methodology — run UNFIXED code first, record outputs, then encode as assertions
  - **GOAL**: Establish baseline behavior for all paths where `isBugCondition(X)` is false; verify these tests PASS on unfixed code before any fix is applied
  - Create `neurocnl/backend/tests/test_simulators_logging_preservation.py`
  - Use `from hypothesis import given, settings` and `from hypothesis import strategies as st` (already a dev dependency in `neurocnl/pyproject.toml`)
  - Register the `"ci"` Hypothesis profile from `neurocnl/neurocnl/tests/properties/conftest.py` (`max_examples=200, derandomize=True`)
  - **Observation step for Sub-case A — Successful Lava run**: Patch `_is_available` → `True`; patch `LavaSimulatorAdapter.run` to return a `LavaSimulatorResult` with known spikes; observe that `run_simulation` returns `SimulatorRunResult` with `status="completed"`, correct `spikes`, `backend_name="lava_sim"`, and no `ERROR`-level log entries
  - **Observation step for Sub-case B — SNNTorch success**: Patch `SnnTorchSimulatorAdapter.run` to return a valid `SnnTorchSimulatorResult`; observe `status="completed"`, correct `voltages`, `backend_name="snntorch_sim"`
  - **Observation step for Sub-case C — SNNTorch dispatch error**: Patch `SnnTorchSimulatorAdapter.run` to raise `SnnTorchDispatchError("snn fail")`; observe HTTP 422, `detail.error == "snntorch_dispatch_failed"`
  - **Property-based test (PBT)**: Generate random SNNTorch-path payloads using Hypothesis strategies (`st.just("snntorch_sim")` for `backend_name`, `st.integers(min_value=10, max_value=200)` for `timesteps`, `st.integers(min_value=0, max_value=99999)` for `seed`); patch `SnnTorchSimulatorAdapter.run` to return a fixed valid result; assert `status_code in {200, 503}` and zero structlog entries with `backend="lava_sim"`
  - **Property-based test (PBT)**: Generate random `LavaSimulatorResult`-compatible spikes dicts using Hypothesis; patch `LavaSimulatorAdapter.run` to return them; assert `status_code == 200`, response `spikes` matches the patched result, and zero `ERROR`-level structlog entries
  - Verify all preservation tests PASS on **UNFIXED** code before proceeding to implementation
  - **EXPECTED OUTCOME**: All preservation tests pass (baseline behavior is stable and captured)
  - Mark task complete when tests are written, run, and confirmed passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [ ] 3. Fix: Add structured logging to `neurocnl/backend/app/routers/simulators.py`

  - [ ] 3.1 Add `structlog` import and module-level logger
    - In `neurocnl/backend/app/routers/simulators.py`, after the `import os` line, add two lines:
      `import structlog` and `logger = structlog.get_logger(__name__)`
    - Match the exact pattern used in `deploy.py` (after existing `import os` equivalent) and `backend/app/main.py`
    - This is the only module-level change; it carries no runtime cost on any hot path
    - _Bug_Condition: isBugCondition(X) where X.backend = "lava_sim" AND X.outcome ∈ {gateway_timeout, dispatch_error, unexpected_exception, missing_dependency}_
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [ ] 3.2 Add `logger.warning` before the 503 raise in the missing-dependency block
    - Locate the block: `if body.backend_name == "lava_sim" and not lava_in_process and not lava_worker_url:`
    - Immediately before `raise HTTPException(status_code=503, …)`, insert `logger.warning("lava_sim_dependency_missing", backend="lava_sim", reason="missing_dependency")`
    - The `raise HTTPException` line itself MUST NOT be altered
    - _Bug_Condition: X.outcome = missing_dependency_
    - _Expected_Behavior: structured WARNING entry with backend="lava_sim" and reason="missing_dependency" written before the HTTPException is raised_
    - _Requirements: 2.4_

  - [ ] 3.3 Add `logger.info` immediately before `LavaSimulatorAdapter().run()`
    - Locate `lava_result = LavaSimulatorAdapter().run(…)` in the `if body.backend_name == "lava_sim":` dispatch block
    - Immediately before it, insert `logger.info("lava_sim_dispatch_started", backend="lava_sim", timesteps=body.timesteps, runtime_mode="in_process" if lava_in_process else "remote")`
    - This entry is written synchronously before the long-running `.run()` call so it lands in the log even if the API gateway drops the connection mid-execution
    - _Bug_Condition: X.outcome = gateway_timeout (pre-call window)_
    - _Expected_Behavior: at least one structured entry with backend="lava_sim" is present in logs before run() is entered_
    - _Requirements: 2.1_

  - [ ] 3.4 Add `logger.error` inside the existing `except LavaDispatchError` block
    - Locate `except LavaDispatchError as exc:` in the Lava dispatch block
    - Add `logger.error("lava_sim_dispatch_error", backend="lava_sim", exc_type=type(exc).__name__, exc_message=str(exc))` as the first statement inside that block, before `raise HTTPException`
    - The `raise HTTPException(status_code=422, …) from exc` line MUST NOT be altered
    - _Bug_Condition: X.outcome = dispatch_error_
    - _Expected_Behavior: structured ERROR entry with backend="lava_sim", exc_type="LavaDispatchError", exc_message=str(exc) written before HTTPException is raised_
    - _Requirements: 2.2_

  - [ ] 3.5 Add bare `except Exception` clause with `logger.exception` immediately after the `LavaDispatchError` block
    - Immediately after the closing of `except LavaDispatchError as exc:` block, add a new clause: `except Exception as exc:  # noqa: BLE001` containing `logger.exception("lava_sim_unexpected_error", backend="lava_sim", exc_type=type(exc).__name__, exc_message=str(exc))` followed by `raise`
    - `logger.exception` (structlog convention) automatically includes the full traceback via the `structlog.dev.set_exc_info` processor configured in `neurocnl/logging_config.py`
    - The bare `raise` MUST be present to re-raise the original exception unchanged; do NOT wrap it
    - _Bug_Condition: X.outcome = unexpected_exception_
    - _Expected_Behavior: structured ERROR entry with backend="lava_sim", exc_type, exc_message, and full traceback written before exception propagates_
    - _Preservation: existing LavaDispatchError handler and all non-Lava paths are unaffected_
    - _Requirements: 2.3_

  - [ ] 3.6 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Lava Failure Paths Now Produce Structured Log Entries
    - **IMPORTANT**: Re-run the SAME test file from task 1 (`test_simulators_logging_exploration.py`) — do NOT write a new test
    - The test from task 1 encodes the expected behavior; when it passes it confirms the fix is correct
    - **Specifically verify**:
      - Sub-case A (missing-dep): `captured_logs` contains exactly one entry with `level="warning"`, `backend="lava_sim"`, `reason="missing_dependency"`
      - Sub-case B (LavaDispatchError): `captured_logs` contains exactly one entry with `level="error"`, `backend="lava_sim"`, `exc_type="LavaDispatchError"`
      - Sub-case C (unexpected exception): `captured_logs` contains exactly one entry with `level="error"` (from `logger.exception`), `backend="lava_sim"`, `exc_type="RuntimeError"`
      - Sub-case D (structural check): The source file now contains `import structlog` and a `logger =` assignment
    - Run: `PYTHONPATH=neurocnl python -m pytest neurocnl/backend/tests/test_simulators_logging_exploration.py -v`
    - **EXPECTED OUTCOME**: All sub-cases PASS (confirms the fix works for every failure mode)
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [ ] 3.7 Verify preservation tests still pass after the fix
    - **Property 2: Preservation** - Non-Buggy Paths Remain Identical After Fix
    - **IMPORTANT**: Re-run the SAME test file from task 2 (`test_simulators_logging_preservation.py`) — do NOT write new tests
    - Run: `PYTHONPATH=neurocnl python -m pytest neurocnl/backend/tests/test_simulators_logging_preservation.py -v`
    - **EXPECTED OUTCOME**: All property-based and example-based preservation tests PASS (no regressions on SNNTorch paths, successful Lava path, or pre-dispatch pipeline)
    - Also run the pre-existing router suite: `PYTHONPATH=neurocnl python -m pytest neurocnl/backend/tests/test_simulators_router.py -v`
    - **EXPECTED OUTCOME**: All pre-existing `test_simulators_router.py` tests still PASS

- [ ] 4. Checkpoint — Ensure all tests pass
  - Run the full backend test suite: `PYTHONPATH=neurocnl python -m pytest neurocnl/backend/tests/ -v`
  - Run linting: `ruff check neurocnl/backend/app/routers/simulators.py`
  - Run type checking: `mypy neurocnl/backend/app/routers/simulators.py`
  - Confirm zero new `ERROR`-level structlog entries appear during a successful `POST /api/simulators/run` with `backend_name="snntorch_sim"` (integration-level preservation check)
  - Confirm no `import structlog` side effects affect the existing `test_simulators_router.py` tests — all must still pass unchanged
  - Ensure all tests pass; ask the user if questions arise
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

## Notes

- The fix touches **exactly one file**: `neurocnl/backend/app/routers/simulators.py`. No changes to `lava_simulator.py` are required.
- The five additions are purely additive — no existing lines are modified or removed.
- The `structlog.testing.capture_logs()` context manager (available in `structlog >= 21.5.0`) binds a `LogCapture` processor for the duration of the `with` block and collects all log events as a list of dicts; it is the correct tool for asserting log output in unit tests without needing real I/O.
- The gateway-timeout requirement (2.1) is satisfied structurally: writing `logger.info(…)` before `LavaSimulatorAdapter().run()` ensures at least one log entry exists in the server log regardless of whether the gateway drops the connection before `.run()` returns. This does not require a runtime timeout test — Sub-case D in task 1 is a static structural assertion sufficient to confirm the fix.
- All Hypothesis-based preservation tests should be placed in the `"ci"` profile (`@settings(max_examples=200, derandomize=True)`) for determinism in CI.
- The `# noqa: BLE001` comment on the bare `except Exception` clause suppresses the ruff `BLE001` ("blind exception") lint warning, consistent with the existing pattern already used in `lava_simulator.py` (lines 248, 296, 337).
