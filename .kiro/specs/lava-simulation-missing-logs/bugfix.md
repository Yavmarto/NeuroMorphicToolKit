# Bugfix Requirements Document

## Introduction

When a Lava simulation fails in CNL Studio — whether due to a gateway timeout cutting off the async
handler before it completes, a `LavaDispatchError` during dispatch, an unexpected Python exception,
or a missing `lava` / `NEUROCNL_LAVA_WORKER_URL` dependency — no structured log entry is written to
the backend server logs. This makes server-side failure diagnosis impossible: the HTTP 422 or 503
response is visible to the frontend, but operations staff and developers have no server-side
evidence of why the run failed.

The SNNTorch path does not exhibit this problem because those simulations complete quickly enough
that Python's exception handlers execute before the gateway connection drops. The Lava path is
uniquely affected because the gateway can time out before `LavaSimulatorAdapter().run()` finishes,
causing the `except LavaDispatchError` block — which is currently the only place an error could
theoretically be logged — to be skipped entirely. Additionally, even on non-timeout failures there
is currently no `logger.error` or `logger.exception` call anywhere in the Lava dispatch path.

This fix is scoped exclusively to the missing-logging concern. Fixing the underlying gateway
timeout behaviour is tracked separately.

---

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a Lava simulation request is dispatched and the API gateway times out before
`LavaSimulatorAdapter().run()` returns THEN the system writes no log entry to the backend
server logs for that failure.

1.2 WHEN `LavaSimulatorAdapter().run()` raises `LavaDispatchError` (e.g., the Lava worker
returns an error response) THEN the system raises an `HTTPException` but writes no
`logger.error` or `logger.exception` entry to the backend server logs.

1.3 WHEN `LavaSimulatorAdapter().run()` raises an unexpected exception (any exception that is
not `LavaDispatchError`) THEN the system produces no structured log entry in the backend server
logs before the exception propagates.

1.4 WHEN the dependency check determines that the `lava` package is absent and
`NEUROCNL_LAVA_WORKER_URL` is not set THEN the system raises an `HTTPException` (503) but writes
no log entry recording that the simulation was rejected due to a missing dependency.

### Expected Behavior (Correct)

2.0 A "structured log entry" in requirements 2.1–2.4 is defined as a log record containing at minimum: `level` (ERROR or WARNING), `logger_name` (the Python logger name used in the handler), `message` (a human-readable description of the failure), and `backend` (the string `"lava_sim"`).

2.1 WHEN a Lava simulation request is dispatched and the API gateway times out before `LavaSimulatorAdapter().run()` returns THEN the system SHALL write at least one structured `ERROR`-level log entry — containing `backend = "lava_sim"` and a `message` field identifying the event as a Lava simulation failure — to the backend server logs before the gateway connection is dropped, regardless of whether the async handler itself completes.

2.2 WHEN `LavaSimulatorAdapter().run()` raises `LavaDispatchError` THEN the system SHALL write a structured `ERROR`-level log entry containing `backend = "lava_sim"`, the exception class name, and the exception message to the backend server logs before raising the `HTTPException`.

2.3 WHEN `LavaSimulatorAdapter().run()` raises an unexpected exception (any exception that is not `LavaDispatchError`) THEN the system SHALL write a structured `ERROR`-level log entry containing `backend = "lava_sim"`, the exception class name, the exception message, and a full traceback to the backend server logs before allowing the exception to propagate.

2.4 WHEN the dependency check determines that the `lava` package is absent and `NEUROCNL_LAVA_WORKER_URL` is not set THEN the system SHALL write a structured `WARNING`-level log entry containing `backend = "lava_sim"` and `reason = "missing_dependency"` to the backend server logs before raising the `HTTPException` (503).

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a Lava simulation completes successfully THEN the system SHALL CONTINUE TO return a `SimulatorRunResult` object with the same type and identical top-level field values as before this change, and the added logging SHALL introduce no more than 5 ms of additional wall-clock latency to the successful path.

3.2 WHEN an SNNTorch simulation is dispatched and fails with `SnnTorchDispatchError` THEN the system SHALL CONTINUE TO propagate the exception through the same exception-handling path as before, returning the same HTTP status code and the same response body field set as the pre-fix behavior.

3.3 WHEN an SNNTorch simulation completes successfully THEN the system SHALL CONTINUE TO return a `SimulatorRunResult` object with the same type and identical top-level field values as before this change.

3.4 WHEN the CNL compilation step fails with a `CompileError` THEN the system SHALL CONTINUE TO return HTTP 400 with a response body containing the same field set (`error`, `detail`) as the pre-fix behavior.

3.5 WHEN the NIR graph support classification returns `unsupported` THEN the system SHALL CONTINUE TO return HTTP 422 with a response body containing the same field set (`error`, `detail`) as the pre-fix behavior.

3.6 WHEN the stimulus parsing step fails with a `StimulusError` THEN the system SHALL CONTINUE TO return HTTP 422 with a response body containing the same field set (`error`, `detail`) as the pre-fix behavior.

---

## Bug Condition Pseudocode

### Bug Condition Function

```pascal
FUNCTION isBugCondition(X)
  INPUT:  X — a Lava simulation dispatch attempt
          X.outcome ∈ {gateway_timeout, dispatch_error, unexpected_exception, missing_dependency}
  OUTPUT: boolean

  RETURN X.backend = "lava_sim"
     AND (  X.outcome = gateway_timeout
         OR X.outcome = dispatch_error
         OR X.outcome = unexpected_exception
         OR X.outcome = missing_dependency )
END FUNCTION
```

### Fix-Checking Property

```pascal
// Property: Fix Checking — every Lava failure produces a backend log entry
FOR ALL X WHERE isBugCondition(X) DO
  run_simulation'(X)          // invoke the fixed handler
  ASSERT backend_logs CONTAINS entry WHERE
      entry.level  ∈ {ERROR, WARNING}
    AND entry.backend = "lava_sim"
    AND entry.outcome = X.outcome
END FOR
```

(`run_simulation'` denotes the fixed version of `run_simulation` in `simulators.py`.)

### Preservation Property

```pascal
// Property: Preservation Checking — non-Lava and successful paths are unchanged
FOR ALL X WHERE NOT isBugCondition(X) DO
  ASSERT run_simulation(X) = run_simulation'(X)
END FOR
```
