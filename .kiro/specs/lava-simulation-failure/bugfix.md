# Bugfix Requirements Document

## Introduction

Lava simulation fails with HTTP 422 ("Lava simulation failed: timed out" / "lava_dispatch_failed") for every CNL template submitted through CNL Studio, including simple templates that succeed under SNNTorch. Both backends share the same CNL → NIR compilation pipeline, so the NIR graph is valid. The root cause is that `LavaSimulatorAdapter.run()` is a blocking synchronous call invoked directly inside an `async` FastAPI handler (`POST /api/simulators/run`). This blocks the event loop for the duration of the Lava simulation — which can involve spawning sub-processes and initialising the Lava runtime — causing the HTTP layer to time out before the simulation returns. Because the timeout originates at the transport/gateway layer rather than inside a Python exception handler, no structured error is logged to the backend and no diagnostic detail appears in the application logs.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a user submits any CNL spec to `POST /api/simulators/run` with `backend_name = "lava_sim"` THEN the system returns HTTP 422 with the message "Lava simulation failed: timed out" without producing any backend log entry for the failure.

1.2 WHEN `LavaSimulatorAdapter().run()` is called inside the `async def run_simulation` handler THEN the system blocks the entire asyncio event loop for the duration of Lava process initialisation and execution, preventing the server from handling any other request and triggering gateway-level timeouts.

1.3 WHEN the gateway timeout fires before `LavaSimulatorAdapter.run()` returns THEN the system discards the request before the FastAPI exception handlers can execute, so no `logger.exception` or `logger.error` call is reached and the failure is invisible in backend logs.

1.4 WHEN the same CNL spec is submitted with `backend_name = "snntorch_sim"` THEN the system completes successfully, confirming the NIR graph and CNL compilation stages are not at fault.

### Expected Behavior (Correct)

2.1 WHEN a user submits a CNL spec to `POST /api/simulators/run` with `backend_name = "lava_sim"` THEN the system SHALL keep the asyncio event loop unblocked during simulation execution, so that the server continues to accept and complete other HTTP requests while the Lava simulation is running.

2.2 WHEN `LavaSimulatorAdapter.run()` raises any exception during execution THEN the system SHALL log an `ERROR`-level entry containing at minimum: the exception class name, the exception message, and the CNL spec hash or first 64 characters of the spec string, before returning the HTTP response to the caller.

2.3 WHEN the Lava simulation exceeds 30 seconds of wall-clock execution time THEN the system SHALL return HTTP 422 with a response body whose top-level fields are `error = "lava_dispatch_failed"`, `message` (a human-readable timeout description), and `source = "lava_sim"`.

2.4 WHEN `LavaSimulatorAdapter.run()` completes successfully THEN the system SHALL return HTTP 200 with a response body whose top-level fields include `spikes` (a dict mapping neuron identifiers to spike-time arrays) and `backend_name = "lava_sim"`.

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a user submits a CNL spec with `backend_name = "snntorch_sim"` THEN the system SHALL CONTINUE TO return HTTP 200 with a response body containing at minimum the fields `spikes` (dict) and `voltages` (dict), identical in HTTP status and top-level response fields to the behavior before this fix.

3.2 WHEN `compile_to_nir` fails for a malformed CNL spec THEN the system SHALL CONTINUE TO return HTTP 400 with a response body containing both `error` and `detail` fields, regardless of which backend was requested.

3.3 WHEN the NIR graph contains node types unsupported by `lava_sim` THEN the system SHALL CONTINUE TO return HTTP 422 with `error = "nir_unsupported"` before any simulation dispatch is attempted.

3.4 WHEN `lava-nc` is not installed and `NEUROCNL_LAVA_WORKER_URL` is unset THEN the system SHALL CONTINUE TO return HTTP 503 with `error = "missing_dependency"`, and this check SHALL occur before any simulation dispatch.

3.5 WHEN `lava-nc` is not installed locally but `NEUROCNL_LAVA_WORKER_URL` is set THEN the system SHALL CONTINUE TO dispatch to the remote worker and return HTTP 200 with a response body containing at minimum `spikes` (dict) and `backend_name = "lava_sim"`, at the same top-level structure as the local execution path.

3.6 WHEN the `/api/simulators/capabilities` endpoint is called THEN the system SHALL CONTINUE TO return HTTP 200 with a response body in which each backend entry contains at minimum `backend_name` (string), `available` (boolean), and `nir_support` (boolean).
