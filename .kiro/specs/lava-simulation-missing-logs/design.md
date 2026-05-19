# Lava Simulation Missing Logs — Bugfix Design

## Overview

When a Lava simulation fails in `neurocnl/backend/app/routers/simulators.py`, the
`run_simulation` handler produces no structured log entry in any of the four failure
modes: gateway timeout, `LavaDispatchError`, unexpected exception, and missing dependency.
This makes server-side failure diagnosis impossible because the HTTP 422 / 503 response
visible to the frontend has no corresponding server-side evidence trail.

The fix is purely additive: insert `structlog` calls at exactly four points in
`simulators.py` — one `logger.warning` for the missing-dependency check and three
`logger.error` / `logger.exception` calls in the Lava dispatch block — using the same
`structlog.get_logger(__name__)` pattern already established in `deploy.py` and other
backend routers. No changes to `lava_simulator.py` are required.

The gateway-timeout case (Requirement 2.1) is addressed by logging _before_ the
long-running `LavaSimulatorAdapter().run()` call, so at least one structured entry
lands in the backend logs regardless of whether the async handler completes.

---

## Glossary

- **Bug_Condition (C)**: A Lava simulation dispatch attempt whose outcome is one of
  `gateway_timeout`, `dispatch_error`, `unexpected_exception`, or `missing_dependency`.
- **Property (P)**: The desired behavior for any C(X) input — the backend server logs
  contain at least one structured entry with `level ∈ {ERROR, WARNING}` and
  `backend = "lava_sim"`.
- **Preservation**: All existing response shapes, HTTP status codes, and code paths for
  successful Lava runs, all SNNTorch paths, and all non-simulator routes must be
  completely unaffected.
- **`run_simulation`**: The FastAPI POST handler in
  `neurocnl/backend/app/routers/simulators.py` that compiles CNL to NIR and dispatches
  to a simulator backend.
- **`LavaSimulatorAdapter().run()`**: The long-running coroutine-adjacent call in
  `neurocnl/neurocnl/runtime/lava_simulator.py` that blocks the handler thread for the
  duration of the simulation; the gateway can drop the connection before it returns.
- **structlog**: The structured logging library already configured via
  `neurocnl/neurocnl/logging_config.py` and used by every other backend router.
  Instantiated as `logger = structlog.get_logger(__name__)`.
- **`backend = "lava_sim"`**: The required keyword argument that must appear in every
  log call added by this fix, enabling log-aggregation filters to isolate Lava events.

---

## Bug Details

### Bug Condition

The bug manifests whenever a Lava simulation attempt reaches one of the four
terminal failure states in `run_simulation`. The handler either raises
`HTTPException` (missing-dependency and `LavaDispatchError` branches) or allows an
exception to propagate (unexpected-exception branch), but in every case it does so
silently — `simulators.py` contains no `import structlog` and no `logger` instance.

**Formal Specification:**

```
FUNCTION isBugCondition(X)
  INPUT:  X — a Lava simulation dispatch attempt
          X.outcome ∈ {gateway_timeout, dispatch_error,
                       unexpected_exception, missing_dependency}
  OUTPUT: boolean

  RETURN X.backend = "lava_sim"
     AND (  X.outcome = gateway_timeout
         OR X.outcome = dispatch_error
         OR X.outcome = unexpected_exception
         OR X.outcome = missing_dependency )
END FUNCTION
```

### Examples

- **Gateway timeout**: Operator triggers a large simulation; the API gateway drops
  the connection at T+30 s. The `except LavaDispatchError` block is never reached,
  no log entry appears.  
  _Expected (fixed)_: a `logger.error(…, backend="lava_sim", event="lava_sim_dispatch_started")`
  entry was written before the `.run()` call began, so operations staff can see it.

- **LavaDispatchError**: The Lava worker returns an error response; `.run()` raises
  `LavaDispatchError("Remote Lava worker request failed: connection refused")`. The
  handler raises `HTTPException(422)` with no log entry.  
  _Expected (fixed)_: `logger.error(…, backend="lava_sim", exc_type="LavaDispatchError",
  exc_message="…")` is written before the `HTTPException` is raised.

- **Unexpected exception**: An `AssertionError` escapes `.run()`. The handler
  propagates it with no log entry.  
  _Expected (fixed)_: `logger.exception(…, backend="lava_sim", exc_type="AssertionError")`
  writes a full traceback before propagation.

- **Missing dependency**: Both `lava` package and `NEUROCNL_LAVA_WORKER_URL` are
  absent. The handler raises `HTTPException(503)` immediately with no log entry.  
  _Expected (fixed)_: `logger.warning(…, backend="lava_sim", reason="missing_dependency")`
  is written before the `HTTPException`.

---

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**

- A successful Lava simulation MUST continue to return `SimulatorRunResult` with the
  same type and identical top-level field values; added logging MUST introduce no more
  than 5 ms of additional wall-clock latency on the success path.
- All SNNTorch dispatch logic (`SnnTorchDispatchError` path, successful path) is
  entirely outside the touched code region and MUST be unaffected.
- `CompileError`, `nir_unsupported`, and `StimulusError` branches are earlier in the
  pipeline than the Lava block and MUST be unaffected.
- The HTTP status codes and response body field shapes for all existing error responses
  (400, 422, 503) MUST remain identical.

**Scope:**

All inputs where `isBugCondition(X)` is false — successful Lava runs, all SNNTorch
inputs, all non-Lava pipeline failures — must be completely unaffected. The only
observable change for those inputs is the addition of the `import structlog` and
`logger = structlog.get_logger(__name__)` lines at module import time, which carry no
runtime cost on the hot path.

---

## Hypothesized Root Cause

There is no ambiguity here — the root cause is identified directly by source inspection:

1. **No `structlog` import in `simulators.py`**: The file has zero `import structlog`
   or `import logging` statements. Every other backend router (`deploy.py`,
   `prosthetic/export.py`, etc.) carries `import structlog` and
   `logger = structlog.get_logger(__name__)`. This line was simply never added to
   `simulators.py`.

2. **No `logger.error` or `logger.warning` call in the Lava dispatch block**: Even if
   a logger existed, the `except LavaDispatchError` block (lines ~289–302 in the
   current file) only constructs and raises an `HTTPException`; there is no log call.
   The bare `except Exception` case is entirely absent.

3. **No pre-call log entry for the gateway-timeout scenario**: The
   `LavaSimulatorAdapter().run()` call is entered without any preceding log entry,
   so if the gateway drops the connection before the call returns, there is no trace
   of the simulation attempt in the logs.

4. **Missing-dependency branch is also silent**: The 503 branch for absent `lava`
   and `NEUROCNL_LAVA_WORKER_URL` raises `HTTPException` without calling any logger.

---

## Correctness Properties

Property 1: Bug Condition — Every Lava failure produces a backend log entry

_For any_ dispatch attempt X where `isBugCondition(X)` is true, the fixed
`run_simulation` handler SHALL write at least one structured log entry to the backend
server logs before the response is sent or the exception propagates. That entry SHALL
contain `level ∈ {ERROR, WARNING}`, `backend = "lava_sim"`, and a `message` field
identifying the failure. For `dispatch_error` and `unexpected_exception` outcomes the
entry SHALL additionally contain the exception class name and message; for
`unexpected_exception` it SHALL include a full traceback; for `missing_dependency` it
SHALL contain `reason = "missing_dependency"`.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

Property 2: Preservation — Non-buggy inputs are unaffected

_For any_ dispatch attempt X where `isBugCondition(X)` is false (successful Lava run,
any SNNTorch input, any pre-dispatch pipeline failure), the fixed `run_simulation`
SHALL produce exactly the same return value or exception — including HTTP status code,
response body, and exception type — as the original `run_simulation`, preserving all
existing behavior.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

---

## Fix Implementation

### Changes Required

The fix touches exactly one file. `lava_simulator.py` already has a `logger` instance
and appropriate `logger.info` / `logger.warning` / `logger.debug` calls; no changes
are needed there.

**File**: `neurocnl/backend/app/routers/simulators.py`

**Step 1 — Add `structlog` import and module-level logger** (near the top of the file,
after the existing `import os` line, matching the pattern in `deploy.py`):

```python
import structlog

logger = structlog.get_logger(__name__)
```

**Step 2 — Missing-dependency log (addresses Requirement 2.4)**

In the existing `if body.backend_name == "lava_sim" and not lava_in_process and not lava_worker_url:` block, add a `logger.warning` call immediately before the `raise HTTPException(503, …)`:

```python
logger.warning(
    "lava_sim_dependency_missing",
    backend="lava_sim",
    reason="missing_dependency",
)
raise HTTPException(
    status_code=503,
    detail=build_backend_failure_detail(…),
)
```

**Step 3 — Pre-dispatch entry-point log (addresses Requirement 2.1)**

Immediately before `lava_result = LavaSimulatorAdapter().run(…)`, add:

```python
logger.info(
    "lava_sim_dispatch_started",
    backend="lava_sim",
    timesteps=body.timesteps,
    runtime_mode="in_process" if lava_in_process else "remote",
)
```

This entry is written synchronously before the long-running `.run()` call, so it lands
in the log even if the gateway drops the connection mid-execution.

**Step 4 — `LavaDispatchError` log (addresses Requirement 2.2)**

Inside `except LavaDispatchError as exc:`, add a `logger.error` call before the
`raise HTTPException`:

```python
except LavaDispatchError as exc:
    logger.error(
        "lava_sim_dispatch_error",
        backend="lava_sim",
        exc_type=type(exc).__name__,
        exc_message=str(exc),
    )
    raise HTTPException(
        status_code=422,
        detail=build_backend_failure_detail(…),
    ) from exc
```

**Step 5 — Unexpected-exception log (addresses Requirement 2.3)**

Add a bare `except Exception` clause immediately after the `except LavaDispatchError`
block to catch and log unexpected exceptions before re-raising:

```python
except Exception as exc:  # noqa: BLE001
    logger.exception(
        "lava_sim_unexpected_error",
        backend="lava_sim",
        exc_type=type(exc).__name__,
        exc_message=str(exc),
    )
    raise
```

`logger.exception` (a structlog convention) automatically includes the full traceback
via the `structlog.dev.set_exc_info` processor already configured in
`neurocnl/logging_config.py`.

### No Changes to `lava_simulator.py`

`lava_simulator.py` already uses `logger = logging.getLogger(__name__)` with
`logger.info`, `logger.warning`, and `logger.debug` calls. Those entries are written
inside the adapter, but they are insufficient for Requirements 2.1–2.4 because the
adapter's logger is a stdlib logger (not structlog), and the adapter does not write
`ERROR`-level entries with `backend = "lava_sim"` in the failure paths. The router
is the right ownership boundary for structured failure audit logs.

---

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, run exploratory tests against
the **unfixed** code to surface the absence of log entries (confirming the bug), then
verify the fix produces entries and preserves all existing behavior.

### Exploratory Bug Condition Checking

**Goal**: Confirm that the unfixed `run_simulation` produces zero log entries for each
of the four failure modes. Refute or confirm the root-cause hypothesis that the absence
of a `structlog` logger is the complete cause.

**Test Plan**: Patch `LavaSimulatorAdapter.run` and the dependency-check helper with
test doubles. Capture structlog output. Assert that no `backend = "lava_sim"` entry
appears. Run on **unfixed** code.

**Test Cases**:

1. **Missing-dependency path** (will produce zero log entries on unfixed code): Call
   `run_simulation` with `backend_name="lava_sim"` when `_is_available("lava")` returns
   `False` and `_lava_worker_url()` returns `None`. Assert `captured_logs == []`.

2. **LavaDispatchError path** (will produce zero log entries on unfixed code): Patch
   `LavaSimulatorAdapter.run` to raise `LavaDispatchError("test error")`. Assert
   `captured_logs == []`.

3. **Unexpected-exception path** (will produce zero log entries on unfixed code): Patch
   `LavaSimulatorAdapter.run` to raise `RuntimeError("unexpected")`. Assert
   `captured_logs == []`.

4. **Gateway-timeout / pre-call window** (will produce zero log entries on unfixed
   code): Inspect source — assert no log call precedes the `.run()` invocation. This is
   a static / structural check rather than a runtime one.

**Expected Counterexamples**: All four assertions pass (no entries found), confirming
the root cause is purely the absence of logger setup and call sites.

### Fix Checking

**Goal**: Verify that for all inputs where `isBugCondition(X)` holds, the fixed handler
writes at least one structured entry with the required fields.

**Pseudocode:**

```
FOR ALL X WHERE isBugCondition(X) DO
  captured_logs := []
  run_simulation_fixed(X)          -- may raise HTTPException or re-raise
  ASSERT EXISTS entry IN captured_logs WHERE
      entry.level  ∈ {ERROR, WARNING}
    AND entry.backend = "lava_sim"
    AND (X.outcome ≠ missing_dependency → entry.exc_type IS NOT NULL)
    AND (X.outcome = unexpected_exception → entry.traceback IS NOT NULL)
    AND (X.outcome = missing_dependency → entry.reason = "missing_dependency")
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where `isBugCondition(X)` is false, the fixed
handler produces the same return value or exception as the original.

**Pseudocode:**

```
FOR ALL X WHERE NOT isBugCondition(X) DO
  result_original  := run_simulation_original(X)   -- capture type + value
  result_fixed     := run_simulation_fixed(X)
  ASSERT result_original = result_fixed
END FOR
```

**Testing Approach**: Property-based testing is recommended for the preservation
property because:
- It generates many combinations of valid NIR graphs, stimulus parameters, and backend
  names automatically.
- It catches regressions in the SNNTorch path or pre-dispatch pipeline stages that
  manual tests might miss.
- It provides strong guarantees that the added `import structlog` and logger
  instantiation have zero effect on non-Lava-failure outcomes.

**Test Plan**: Observe behavior on unfixed code first for each preserved path, then
write property-based tests that assert the same response shape and status code after
the fix.

**Test Cases**:

1. **Successful Lava run preservation**: Patch `LavaSimulatorAdapter.run` to return a
   valid `LavaSimulatorResult`. Assert the fixed handler returns a `SimulatorRunResult`
   with identical top-level fields and no additional latency > 5 ms.

2. **SNNTorch success preservation**: Patch `SnnTorchSimulatorAdapter.run` to return a
   valid result. Assert the fixed handler returns the same `SimulatorRunResult` shape.

3. **SNNTorch dispatch-error preservation**: Patch `SnnTorchSimulatorAdapter.run` to
   raise `SnnTorchDispatchError`. Assert the same HTTP 422 response body.

4. **CompileError preservation**: Pass an invalid CNL spec. Assert HTTP 400 with the
   same `error` / `detail` field set.

5. **NIR unsupported preservation**: Patch `classify_nir_graph` to return `unsupported`.
   Assert HTTP 422 with the same field set.

6. **StimulusError preservation**: Patch `parse_stimulus` to raise `StimulusError`.
   Assert HTTP 422 with the same field set.

### Unit Tests

- Assert `logger.warning` is called with `backend="lava_sim"` and
  `reason="missing_dependency"` when the dependency check fails.
- Assert `logger.error` is called with `backend="lava_sim"`, `exc_type`, and
  `exc_message` when `LavaDispatchError` is raised.
- Assert `logger.exception` is called with `backend="lava_sim"`, `exc_type`, and
  `exc_message` when an unexpected exception is raised, and that the exception
  propagates unchanged.
- Assert `logger.info` with `backend="lava_sim"` and `event="lava_sim_dispatch_started"`
  is called before `LavaSimulatorAdapter().run()` on every Lava dispatch (success
  and failure).

### Property-Based Tests

- Generate random valid `SimulatorRunRequest` objects with `backend_name="snntorch_sim"`
  and a patched adapter; assert the response shape is identical before and after the
  fix across all inputs.
- Generate random `SimulatorRunRequest` objects with `backend_name="lava_sim"` where
  `LavaSimulatorAdapter.run` is patched to succeed; assert no `ERROR`-level log entry
  is written and the return type matches `SimulatorRunResult`.
- Generate random failure payloads for `LavaDispatchError` (varying `diagnostics`
  strings); assert that each produces exactly one `ERROR` log entry with the correct
  `exc_message` field.

### Integration Tests

- End-to-end: POST `/api/simulators/run` with `backend_name="lava_sim"` against a test
  server configured without the `lava` package. Assert HTTP 503 response **and** that
  the captured structlog output contains a `WARNING`-level entry with
  `backend="lava_sim"` and `reason="missing_dependency"`.
- End-to-end: POST `/api/simulators/run` with `backend_name="lava_sim"` and a patched
  adapter that raises `LavaDispatchError`. Assert HTTP 422 response **and** one
  `ERROR`-level log entry with the required fields.
- Verify that a successful `backend_name="snntorch_sim"` round-trip after the fix
  produces no Lava-tagged log entries and returns the same `SimulatorRunResult` shape.
